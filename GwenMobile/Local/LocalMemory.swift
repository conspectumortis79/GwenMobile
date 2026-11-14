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
        #else
        if let value = systemAvailable, value > 0 { return value }
        #endif
        return physical
    }

    private static var systemAvailable: Int64? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
                                            / MemoryLayout<integer_t>.size)
        let outcome = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard outcome == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let page = Int64(pageSize)
        return Int64(statistics.free_count) * page
            + Int64(statistics.inactive_count) * page
            + Int64(statistics.speculative_count) * page
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
