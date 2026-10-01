import Darwin
import Foundation
import IOKit

/// 80-byte AppleSMC parameter block. Swift would pack this to 76 bytes without
/// the explicit `padding` field after `keyInfo`; the kernel expects 80.
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimit = SMCPLimit()
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = SMCClient.emptyBytes
}

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimit {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpu: UInt32 = 0
    var gpu: UInt32 = 0
    var mem: UInt32 = 0
}

struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

struct SMCKeyMeta {
    var dataSize: UInt32
    var type: String
}

/// Userspace client for the `AppleSMC` IOKit service.
final class SMCClient: @unchecked Sendable {
    static let emptyBytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )

    private let lock = NSLock()
    private var connection: io_connect_t = 0

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connection != 0
    }

    @discardableResult
    func open() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if connection != 0 { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    deinit { close() }

    static func fourCC(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    static func fourCCString(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    func keyInfo(_ key: String) -> SMCKeyMeta? {
        var input = SMCParamStruct()
        input.key = Self.fourCC(key)
        input.data8 = 9
        guard let output = call(&input), output.result == 0 else { return nil }
        return SMCKeyMeta(dataSize: output.keyInfo.dataSize, type: Self.fourCCString(output.keyInfo.dataType))
    }

    func keyExists(_ key: String) -> Bool {
        keyInfo(key) != nil
    }

    func readBytes(_ key: String) -> (meta: SMCKeyMeta, bytes: [UInt8])? {
        guard let meta = keyInfo(key) else { return nil }
        var input = SMCParamStruct()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = meta.dataSize
        input.data8 = 5
        guard let output = call(&input), output.result == 0 else { return nil }
        let count = min(Int(meta.dataSize), 32)
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(count)) }
        return (meta, bytes)
    }

    @discardableResult
    func writeBytes(_ key: String, bytes: [UInt8]) -> Bool {
        guard let meta = keyInfo(key) else { return false }
        var input = SMCParamStruct()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = meta.dataSize
        input.keyInfo.dataType = Self.fourCC(meta.type)
        input.data8 = 6
        withUnsafeMutableBytes(of: &input.bytes) { destination in
            for (index, byte) in bytes.prefix(32).enumerated() {
                destination[index] = byte
            }
        }
        guard let output = call(&input) else { return false }
        return output.result == 0
    }

    func readDouble(_ key: String) -> Double? {
        guard let (meta, bytes) = readBytes(key) else { return nil }
        return Self.decode(type: meta.type, bytes: bytes)
    }

    @discardableResult
    func writeDouble(_ key: String, value: Double) -> Bool {
        guard let meta = keyInfo(key) else { return false }
        var bytes = [UInt8](repeating: 0, count: max(Int(meta.dataSize), 4))
        switch meta.type {
        case "flt ":
            var floatValue = Float(value)
            withUnsafeBytes(of: &floatValue) { raw in
                for index in 0..<4 { bytes[index] = raw[index] }
            }
        case "ui8 ", "flag":
            bytes[0] = UInt8(max(0, min(255, value.rounded())))
        default:
            return false
        }
        return writeBytes(key, bytes: Array(bytes.prefix(Int(meta.dataSize))))
    }

    func fanCount() -> Int {
        Int(readDouble("FNum") ?? 0)
    }

    func enumerateTemperatureKeys() -> [String] {
        let count = keyCount()
        guard count > 0 else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(64)
        for index in 0..<count {
            guard let key = key(at: index) else { continue }
            if key.first == "T" || key.first == "t" {
                keys.append(key)
            }
        }
        return keys
    }

    private func keyCount() -> Int {
        guard let (_, bytes) = readBytes("#KEY"), bytes.count >= 4 else { return 0 }
        return Int(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
    }

    private func key(at index: Int) -> String? {
        var input = SMCParamStruct()
        input.data8 = 8
        input.data32 = UInt32(index)
        guard let output = call(&input), output.result == 0 else { return nil }
        return Self.fourCCString(output.key)
    }

    static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt " where bytes.count >= 4:
            let raw = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))
        case "ui8 " where bytes.count >= 1, "flag" where bytes.count >= 1:
            return Double(bytes[0])
        case "ui16" where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default:
            if type.hasPrefix("sp"), bytes.count >= 2 {
                let fraction = Int(String(type.suffix(1)), radix: 16) ?? 0
                let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
                return Double(raw) / Double(1 << fraction)
            }
            return nil
        }
    }

    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        lock.lock()
        defer { lock.unlock() }
        guard connection != 0 else { return nil }
        var output = SMCParamStruct()
        let size = MemoryLayout<SMCParamStruct>.stride
        var outputSize = size
        let status = IOConnectCallStructMethod(connection, 2, &input, size, &output, &outputSize)
        return status == KERN_SUCCESS ? output : nil
    }
}
