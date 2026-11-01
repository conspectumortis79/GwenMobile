import GwenMobileKit
import Darwin
import Foundation

enum LocalMemory {
    static let hostReserve: Int64 = 3_600_000_000

    static var physical: Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }

    static var available: Int64 {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let value = Int64(os_proc_available_memory())
        if value > 0 { return value }
        #endif
        return physical
    }

    static func canFit(_ bytes: Int64) -> Bool {
        let reserve: Int64 = bytes >= 4_500_000_000 ? 1_500_000_000 : 700_000_000
        return available > bytes + reserve
    }

    static var generationFloor: Int64 {
        max(2_000_000_000, physical / 4)
    }

    static var hasGenerationRoom: Bool {
        available > generationFloor
    }

    static var mlxLimit: Int {
        Int(max(3_500_000_000, physical - 3_000_000_000))
    }

    static func canHost(_ bytes: Int64) -> Bool {
        bytes <= max(0, physical - hostReserve)
    }

    static func minRamGB(for bytes: Int64) -> Int {
        max(8, Int(ceil(Double(bytes + hostReserve) / 1_000_000_000)))
    }

    static var label: String {
        let availableGB = Double(available) / 1_000_000_000
        let physicalGB = Double(physical) / 1_000_000_000
        return String(format: "%.1f / %.1f GB", availableGB, physicalGB)
    }
}
