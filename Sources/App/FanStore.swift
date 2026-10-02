import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI

enum ControlMode: String, CaseIterable, Identifiable {
    case auto
    case quiet
    case balanced
    case performance
    case full
    case custom

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .auto: return "Авто"
        case .quiet: return "Тихий"
        case .balanced: return "Баланс"
        case .performance: return "Нагрузка"
        case .full: return "Максимум"
        case .custom: return "Вручную"
        }
    }

    var percent: Double? {
        switch self {
        case .auto: return nil
        case .quiet: return 0
        case .balanced: return 0.35
        case .performance: return 0.70
        case .full: return 1
        case .custom: return nil
        }
    }
}

@MainActor
final class FanStore: ObservableObject {
    @Published var snapshot = FanSnapshot.empty
    @Published var mode: ControlMode = .auto
    @Published var customRPM: Double = 2000
    @Published var helperInstalled = false
    @Published var helperError: String?
    @Published var lastApplied: String = String(localized: "System")
    @Published var installing = false

    private let smc = SMCClient()
    private var timer: AnyCancellable?
    private var temperatureKeys: [String] = []
    private var wakeObserver: NSObjectProtocol?
    private var customDebounce: DispatchWorkItem?

    func start() {
        _ = smc.open()
        temperatureKeys = smc.enumerateTemperatureKeys()
        helperInstalled = FileManager.default.isExecutableFile(atPath: FanHardware.helperInstallPath)
        refresh()
        customRPM = snapshot.targetRPM == 0 ? snapshot.minRPM : snapshot.targetRPM
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapply() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.mode != .auto {
                    _ = self?.send(.auto)
                }
            }
        }
    }

    func stop() {
        if mode != .auto {
            _ = send(.auto)
        }
        timer?.cancel()
        smc.close()
    }

    func select(_ newMode: ControlMode) {
        mode = newMode
        apply()
    }

    func setCustomRPM(_ rpm: Double) {
        customRPM = rpm
        mode = .custom
        customDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.apply()
        }
        customDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func installHelper() {
        installing = true
        helperError = nil
        Task.detached {
            let result = HelperInstaller.install()
            await MainActor.run {
                self.installing = false
                switch result {
                case .success:
                    self.helperInstalled = true
                    self.refresh()
                    self.apply()
                case .failure(let error):
                    self.helperError = error.localizedDescription
                }
            }
        }
    }

    func restoreAuto() {
        mode = .auto
        apply()
    }

    private func tick() {
        refresh()
        if helperInstalled, mode != .auto {
            _ = send(.ping)
        }
        if let cpu = snapshot.cpuTemp, cpu >= FanHardware.criticalCPU, mode == .quiet {
            mode = .performance
            apply()
        }
    }

    private func reapply() {
        if mode != .auto { apply() }
        refresh()
    }

    private func apply() {
        guard mode != .auto else {
            if helperInstalled { _ = send(.auto) }
            lastApplied = String(localized: "System")
            return
        }
        guard helperInstalled else {
            helperError = String(localized: "A background service with administrator privileges is required.")
            return
        }
        let rpm: Double
        if mode == .custom {
            rpm = customRPM
        } else {
            rpm = FanHardware.rpm(
                forPercent: mode.percent ?? 0,
                minRPM: snapshot.minRPM,
                maxRPM: snapshot.maxRPM
            )
        }
        if send(.set, rpm: rpm) != nil {
            lastApplied = String(format: NSLocalizedString("%d RPM", comment: "Fan speed"), Int(rpm.rounded()))
            helperError = nil
        } else {
            helperError = String(localized: "Could not communicate with the background service.")
        }
    }

    private func refresh() {
        var next = snapshot
        next.model = FanHardware.sysctl("hw.model")
        next.chip = FanHardware.sysctl("machdep.cpu.brand_string")
        if smc.isOpen {
            next.minRPM = smc.readDouble("F0Mn") ?? next.minRPM
            next.maxRPM = smc.readDouble("F0Mx") ?? next.maxRPM
            next.actualRPM = smc.readDouble("F0Ac") ?? next.actualRPM
            next.targetRPM = smc.readDouble("F0Tg") ?? next.targetRPM
            next.mode = Int(smc.readDouble("F0Md") ?? smc.readDouble("F0md") ?? 0)
            next.cpuTemp = maxTemp(prefix: "Tp")
            next.gpuTemp = maxTemp(prefix: "Tg")
            next.nandTemp = maxTemp(prefix: "Ts")
            next.wifiTemp = smc.readDouble("TW0P")
            next.ok = true
        }
        if let helper = send(.status) {
            next.helper = true
            next.manual = helper.manual
            helperInstalled = true
        } else {
            next.helper = false
            next.manual = false
            helperInstalled = FileManager.default.isExecutableFile(atPath: FanHardware.helperInstallPath)
        }
        snapshot = next
    }

    private func maxTemp(prefix: String) -> Double? {
        temperatureKeys
            .filter { $0.hasPrefix(prefix) }
            .compactMap { smc.readDouble($0) }
            .filter { $0 > 1 && $0 < 120 }
            .max()
    }

    @discardableResult
    private func send(_ command: FanControlCommand, rpm: Double? = nil) -> FanSnapshot? {
        let request = FanRequest(cmd: command, rpm: rpm)
        guard let payload = try? JSONEncoder().encode(request) else { return nil }
        var wire = payload
        wire.append(0x0A)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        FanHardware.socketPath.withCString { src in
            withUnsafeMutablePointer(to: &address.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: 104) { path in
                    _ = strncpy(path, src, 103)
                }
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }
        _ = wire.withUnsafeBytes { write(fd, $0.baseAddress, wire.count) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else { return nil }
        let data = Data(buffer.prefix(count)).split(separator: 0x0A).first ?? Data()
        return try? JSONDecoder().decode(FanSnapshot.self, from: data)
    }
}

enum HelperInstaller {
    static func install() -> Result<Void, Error> {
        let helperSrc = Bundle.main.bundlePath + "/Contents/Helpers/fancontrol-helper"
        guard FileManager.default.isExecutableFile(atPath: helperSrc) else {
            return .failure(NSError(domain: "FanControl", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "The helper executable was not found in the app.")
            ]))
        }

        let script = """
        #!/bin/bash
        set -euo pipefail
        mkdir -p /Library/PrivilegedHelperTools
        cp '\(helperSrc)' '\(FanHardware.helperInstallPath)'
        chown root:wheel '\(FanHardware.helperInstallPath)'
        chmod 755 '\(FanHardware.helperInstallPath)'
        cat > '\(FanHardware.launchdPath)' << 'PLIST'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(FanHardware.helperLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(FanHardware.helperInstallPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        PLIST
        chown root:wheel '\(FanHardware.launchdPath)'
        chmod 644 '\(FanHardware.launchdPath)'
        launchctl bootout system/\(FanHardware.helperLabel) 2>/dev/null || true
        launchctl bootstrap system '\(FanHardware.launchdPath)'
        launchctl enable system/\(FanHardware.helperLabel)
        launchctl kickstart -k system/\(FanHardware.helperLabel)
        """

        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("install-fancontrol.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e",
                "do shell script \"/bin/bash \(scriptURL.path)\" with administrator privileges"
            ]
            let err = Pipe()
            process.standardError = err
            process.standardOutput = Pipe()
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return .success(())
            }
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? String(localized: "Installation error")
            return .failure(NSError(domain: "FanControl", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ]))
        } catch {
            return .failure(error)
        }
    }
}
