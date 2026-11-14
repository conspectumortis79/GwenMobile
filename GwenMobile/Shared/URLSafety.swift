import GwenMobileKit
import Darwin
import Foundation

enum URLSafety {
    nonisolated(unsafe) static var hostResolver: @Sendable (String) -> [String] = { resolveAddresses($0) }

    static func isLocalOrPrivate(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased(), !host.isEmpty else { return true }
        return isLocalOrPrivateHost(host)
    }

    static func isLocalOrPrivateHost(_ rawHost: String) -> Bool {
        let host = normalizedHost(rawHost)
        guard !host.isEmpty else { return true }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
            || host.hasSuffix(".internal") || host.hasSuffix(".localdomain") {
            return true
        }
        if let address = ipv4Value(host) { return isPrivateIPv4(address) }
        if let bytes = ipv6Value(host) { return isPrivateIPv6(bytes) }
        return false
    }

    static func isIPAddress(_ rawHost: String) -> Bool {
        let host = normalizedHost(rawHost)
        return ipv4Value(host) != nil || ipv6Value(host) != nil
    }

    static func isLocalOrPrivateResolved(_ url: URL?) async -> Bool {
        guard let url, let host = url.host?.lowercased(), !host.isEmpty else { return true }
        if isLocalOrPrivateHost(host) { return true }
        if isIPAddress(host) { return false }
        let resolver = hostResolver
        let addresses = await Offload.value(priority: .utility) { resolver(host) }
        return addresses.contains { isLocalOrPrivateHost($0) }
    }

    static func isLocalOrPrivateResolvedHost(_ rawHost: String) -> Bool {
        if isLocalOrPrivateHost(rawHost) { return true }
        return hostResolver(rawHost).contains { isLocalOrPrivateHost($0) }
    }

    private static func normalizedHost(_ rawHost: String) -> String {
        var host = rawHost
        while host.hasSuffix(".") { host.removeLast() }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if let zone = host.firstIndex(of: "%") { host = String(host[..<zone]) }
        return host
    }

    private static func ipv4Value(_ host: String) -> UInt32? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if (1...4).contains(parts.count) {
            var values: [UInt32] = []
            for part in parts {
                guard let value = ipv4Part(String(part)) else { return nil }
                values.append(value)
            }
            return ipv4Address(values)
        }
        return nil
    }

    private static func ipv4Address(_ values: [UInt32]) -> UInt32? {
        switch values.count {
        case 1:
            return values[0]
        case 2:
            guard values[0] <= 255, values[1] <= 0xFF_FFFF else { return nil }
            return values[0] << 24 | values[1]
        case 3:
            guard values[0] <= 255, values[1] <= 255, values[2] <= 0xFFFF else { return nil }
            return values[0] << 24 | values[1] << 16 | values[2]
        default:
            guard values.allSatisfy({ $0 <= 255 }) else { return nil }
            return values.reduce(0) { $0 << 8 | $1 }
        }
    }

    private static func ipv4Part(_ part: String) -> UInt32? {
        guard !part.isEmpty else { return nil }
        let lower = part.lowercased()
        if lower.hasPrefix("0x") {
            return UInt32(lower.dropFirst(2), radix: 16)
        }
        if lower.count > 1, lower.first == "0" {
            return UInt32(lower.dropFirst(), radix: 8)
        }
        return UInt32(lower)
    }

    private static func ipv6Value(_ host: String) -> [UInt8]? {
        var parsed = in6_addr()
        guard inet_pton(AF_INET6, host, &parsed) == 1 else { return nil }
        return withUnsafeBytes(of: &parsed) { Array($0) }
    }

    private static func isPrivateIPv4(_ address: UInt32) -> Bool {
        let first = UInt8((address >> 24) & 0xFF)
        let second = UInt8((address >> 16) & 0xFF)
        let third = UInt8((address >> 8) & 0xFF)
        if first == 0 || first == 10 || first == 127 { return true }
        if first == 100, (64...127).contains(second) { return true }
        if first == 169, second == 254 { return true }
        if first == 172, (16...31).contains(second) { return true }
        if first == 192, second == 168 { return true }
        if first == 192, second == 0 { return true }
        if first == 198, (18...19).contains(second) { return true }
        if first == 198, second == 51, third == 100 { return true }
        if first == 203, second == 0, third == 113 { return true }
        if first >= 224 { return true }
        return false
    }

    private static func isPrivateIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.allSatisfy({ $0 == 0 }) { return true }
        if bytes[0..<15].allSatisfy({ $0 == 0 }), bytes[15] == 1 { return true }
        if bytes[0] == 0xFE, (bytes[1] & 0xC0) == 0x80 { return true }
        if bytes[0] == 0xFE, (bytes[1] & 0xC0) == 0xC0 { return true }
        if (bytes[0] & 0xFE) == 0xFC { return true }
        if bytes[0] == 0xFF { return true }
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0D, bytes[3] == 0xB8 { return true }
        if isNAT64(bytes) || isSixToFour(bytes) || isTeredo(bytes) {
            let address = bytes[12...].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            if isNAT64(bytes) { return isPrivateIPv4(address) }
            if isSixToFour(bytes) {
                let embedded = bytes[2...5].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                return isPrivateIPv4(embedded)
            }
            return isPrivateIPv4(address ^ 0xFFFF_FFFF)
        }
        let mapped = bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF
        let compatible = bytes[0..<12].allSatisfy({ $0 == 0 })
        if mapped || compatible {
            let address = bytes[12...].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            return isPrivateIPv4(address)
        }
        return false
    }

    private static func isNAT64(_ bytes: [UInt8]) -> Bool {
        let wellKnown = bytes[0] == 0x00 && bytes[1] == 0x64 && bytes[2] == 0xFF && bytes[3] == 0x9B
            && bytes[4..<12].allSatisfy { $0 == 0 }
        let localUse = bytes[0] == 0x00 && bytes[1] == 0x64 && bytes[2] == 0xFF && bytes[3] == 0x9B
            && bytes[4] == 0x00 && bytes[5] == 0x01
        return wellKnown || localUse
    }

    private static func isSixToFour(_ bytes: [UInt8]) -> Bool {
        bytes[0] == 0x20 && bytes[1] == 0x02
    }

    private static func isTeredo(_ bytes: [UInt8]) -> Bool {
        bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x00 && bytes[3] == 0x00
    }

    private static func resolveAddresses(_ host: String) -> [String] {
        let lower = host.lowercased()
        if [".test", ".invalid", ".example", ".onion"].contains(where: { lower.hasSuffix($0) }) {
            return []
        }
        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen,
                           &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
                addresses.append(String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
            current = entry.pointee.ai_next
        }
        return addresses
    }
}
