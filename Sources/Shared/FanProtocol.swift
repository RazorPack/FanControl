import Darwin
import Foundation

enum FanControlCommand: String, Codable {
    case ping
    case status
    case set
    case auto
}

struct FanRequest: Codable {
    var cmd: FanControlCommand
    var rpm: Double?
}

struct FanSnapshot: Codable, Equatable {
    var ok: Bool
    var error: String?
    var actualRPM: Double
    var targetRPM: Double
    var minRPM: Double
    var maxRPM: Double
    var mode: Int
    var manual: Bool
    var helper: Bool
    var cpuTemp: Double?
    var gpuTemp: Double?
    var nandTemp: Double?
    var wifiTemp: Double?
    var model: String
    var chip: String

    static let empty = FanSnapshot(
        ok: false,
        error: nil,
        actualRPM: 0,
        targetRPM: 0,
        minRPM: 1000,
        maxRPM: 4900,
        mode: 0,
        manual: false,
        helper: false,
        cpuTemp: nil,
        gpuTemp: nil,
        nandTemp: nil,
        wifiTemp: nil,
        model: "",
        chip: ""
    )

    var displayRPM: Int { Int(actualRPM.rounded()) }

    var percent: Double {
        guard maxRPM > minRPM else { return 0 }
        return min(max((actualRPM - minRPM) / (maxRPM - minRPM), 0), 1)
    }
}

enum FanHardware {
    static let socketPath = "/var/run/fancontrol.sock"
    static let helperLabel = "ru.fancontrol.helper"
    static let helperInstallPath = "/Library/PrivilegedHelperTools/ru.fancontrol.helper"
    static let launchdPath = "/Library/LaunchDaemons/ru.fancontrol.helper.plist"
    static let criticalCPU: Double = 95
    static let leaseSeconds: TimeInterval = 20

    static func sysctl(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static func rpm(forPercent percent: Double, minRPM: Double, maxRPM: Double) -> Double {
        minRPM + (maxRPM - minRPM) * min(max(percent, 0), 1)
    }
}
