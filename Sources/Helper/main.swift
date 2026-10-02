import Darwin
import Foundation

/// Privileged daemon: writes SMC fan keys as root and restores automatic
/// control if the GUI disappears (lease timeout).
@main
enum MacFanControlHelper {
    static let smc = SMCClient()
    static var lastLease = Date()
    static var holdingManual = false
    static var desiredRPM: Double?
    static var temperatureKeys: [String] = []
    static let queue = DispatchQueue(label: "ru.macfancontrol.helper")

    static func main() {
        guard geteuid() == 0 else {
            FileHandle.standardError.write(Data("macfancontrol-helper must run as root\n".utf8))
            exit(1)
        }
        guard smc.open() else {
            FileHandle.standardError.write(Data("AppleSMC is unavailable\n".utf8))
            exit(2)
        }
        temperatureKeys = smc.enumerateTemperatureKeys()

        unlink(FanHardware.socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { exit(3) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        FanHardware.socketPath.withCString { src in
            withUnsafeMutablePointer(to: &address.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: 104) { path in
                    _ = strncpy(path, src, 103)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, listen(fd, 8) == 0 else { exit(4) }
        chmod(FanHardware.socketPath, 0o660)
        chown(FanHardware.socketPath, 0, 80) // wheel

        DispatchQueue.global().async {
            while true {
                let client = accept(fd, nil, nil)
                if client >= 0 { handle(client: client) }
            }
        }

        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            queue.sync { maintain() }
        }

        RunLoop.main.run()
    }

    static func handle(client: Int32) {
        defer { close(client) }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(client, &buffer, buffer.count)
        guard count > 0 else { return }
        let data = Data(buffer.prefix(count))
        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
        for line in lines {
            guard let payload = line.data(using: .utf8),
                  let request = try? JSONDecoder().decode(FanRequest.self, from: payload)
            else { continue }
            let response = queue.sync { process(request) }
            if let encoded = try? JSONEncoder().encode(response) {
                var wire = encoded
                wire.append(0x0A)
                _ = wire.withUnsafeBytes { write(client, $0.baseAddress, wire.count) }
            }
        }
    }

    static func process(_ request: FanRequest) -> FanSnapshot {
        lastLease = Date()
        switch request.cmd {
        case .ping, .status:
            break
        case .auto:
            restoreAutomatic()
        case .set:
            if let rpm = request.rpm {
                applyManual(rpm: rpm)
            }
        }
        return snapshot(ok: true, error: nil)
    }

    static func maintain() {
        if holdingManual, Date().timeIntervalSince(lastLease) > FanHardware.leaseSeconds {
            restoreAutomatic()
            return
        }
        if holdingManual, let rpm = desiredRPM {
            reassertManual(rpm: rpm)
        }
    }

    static func applyManual(rpm requested: Double) {
        let limits = fanLimits()
        var rpm = min(max(requested, limits.min), limits.max)
        if let cpu = maxTemp(prefix: "Tp"), cpu >= FanHardware.criticalCPU {
            rpm = max(rpm, FanHardware.rpm(forPercent: 0.7, minRPM: limits.min, maxRPM: limits.max))
        }
        unlockIfNeeded()
        _ = writeMode(1)
        _ = smc.writeDouble("F0Tg", value: rpm)
        holdingManual = true
        desiredRPM = rpm
    }

    static func reassertManual(rpm: Double) {
        let mode = Int(smc.readDouble("F0Md") ?? 0)
        if mode != 1 {
            unlockIfNeeded()
            _ = writeMode(1)
        }
        _ = smc.writeDouble("F0Tg", value: rpm)
    }

    static func restoreAutomatic() {
        _ = writeMode(0)
        if smc.keyExists("Ftst") {
            _ = smc.writeDouble("Ftst", value: 0)
        }
        holdingManual = false
        desiredRPM = nil
    }

    static func unlockIfNeeded() {
        guard smc.keyExists("Ftst") else { return }
        _ = smc.writeDouble("Ftst", value: 1)
        for _ in 0..<40 {
            if writeMode(1) { return }
            usleep(100_000)
        }
    }

    @discardableResult
    static func writeMode(_ mode: Double) -> Bool {
        let key = smc.keyExists("F0Md") ? "F0Md" : "F0md"
        guard smc.writeDouble(key, value: mode) else { return false }
        let readback = smc.readDouble(key) ?? -1
        return Int(readback) == Int(mode)
    }

    static func fanLimits() -> (min: Double, max: Double) {
        (smc.readDouble("F0Mn") ?? 1000, smc.readDouble("F0Mx") ?? 4900)
    }

    static func maxTemp(prefix: String) -> Double? {
        let values = temperatureKeys
            .filter { $0.hasPrefix(prefix) }
            .compactMap { smc.readDouble($0) }
            .filter { $0 > 0 && $0 < 120 }
        return values.max()
    }

    static func snapshot(ok: Bool, error: String?) -> FanSnapshot {
        let limits = fanLimits()
        let mode = Int(smc.readDouble("F0Md") ?? smc.readDouble("F0md") ?? 0)
        return FanSnapshot(
            ok: ok,
            error: error,
            actualRPM: smc.readDouble("F0Ac") ?? 0,
            targetRPM: smc.readDouble("F0Tg") ?? 0,
            minRPM: limits.min,
            maxRPM: limits.max,
            mode: mode,
            manual: holdingManual || mode == 1,
            helper: true,
            cpuTemp: maxTemp(prefix: "Tp"),
            gpuTemp: maxTemp(prefix: "Tg"),
            nandTemp: maxTemp(prefix: "Ts"),
            wifiTemp: smc.readDouble("TW0P"),
            model: FanHardware.sysctl("hw.model"),
            chip: FanHardware.sysctl("machdep.cpu.brand_string")
        )
    }
}
