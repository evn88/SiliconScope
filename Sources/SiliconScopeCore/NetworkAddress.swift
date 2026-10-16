//
//  File:      NetworkAddress.swift
//  Created:   2026-10-15
//  Updated:   2026-10-16
//  Developer: SiliconScope contributors
//  Overview:  Local interface addresses and default-route provenance, without network requests.
//  Notes:     Unlike throughput, address selection includes VPN tunnel interfaces.
//
import Foundation
import Darwin

public struct NetworkAddress: Sendable, Equatable, Codable, Identifiable {
    public var interface: String
    public var address: String
    public var isIPv6: Bool
    public var isPrimary: Bool
    public var id: String { interface + ":" + address }
    public init(interface: String, address: String, isIPv6: Bool, isPrimary: Bool) {
        self.interface = interface; self.address = address
        self.isIPv6 = isIPv6; self.isPrimary = isPrimary
    }
}

public enum IPAddress {
    public static func family(_ address: String) -> Int32? {
        guard !address.isEmpty, address.utf8.count <= 45,
              address.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) ||
                  (97...102).contains($0) || $0 == 46 || $0 == 58 }) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 16)
        if address.withCString({ inet_pton(AF_INET, $0, &bytes) }) == 1 { return AF_INET }
        if address.withCString({ inet_pton(AF_INET6, $0, &bytes) }) == 1 { return AF_INET6 }
        return nil
    }

    static func usableLocal(_ address: String) -> Bool {
        guard let family = family(address) else { return false }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = address.withCString { inet_pton(family, $0, &bytes) }
        if family == AF_INET {
            return bytes[0] != 0 && bytes[0] != 127 && bytes[0] < 224 &&
                !(bytes[0] == 169 && bytes[1] == 254)
        }
        return bytes[0] != 255 && !(bytes[0] == 254 && bytes[1] & 0xC0 == 0x80) &&
            bytes != [UInt8](repeating: 0, count: 16) &&
            bytes != [UInt8](repeating: 0, count: 15) + [1]
    }
}

enum NetworkAddressSampler {
    /// Decode address entries from the network sampler's existing getifaddrs walk.
    static func address(_ ifa: ifaddrs, primaryIPv4: String?, primaryIPv6: String?) -> NetworkAddress? {
        guard ifa.ifa_flags & UInt32(IFF_UP) != 0,
              ifa.ifa_flags & UInt32(IFF_RUNNING) != 0,
              ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
              let name = ifa.ifa_name, let addr = ifa.ifa_addr,
              addr.pointee.sa_family == UInt8(AF_INET) || addr.pointee.sa_family == UInt8(AF_INET6) else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                          nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        let value = String(cBuffer: host)
        guard IPAddress.usableLocal(value) else { return nil }
        let bsd = String(cString: name)
        let v6 = addr.pointee.sa_family == UInt8(AF_INET6)
        return NetworkAddress(interface: bsd, address: value, isIPv6: v6,
                              isPrimary: bsd == (v6 ? primaryIPv6 : primaryIPv4))
    }

    static func ordered(_ addresses: [NetworkAddress]) -> [NetworkAddress] {
        var seen = Set<String>()
        return addresses.filter { seen.insert($0.id).inserted }.sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            if $0.isIPv6 != $1.isIPv6 { return !$0.isIPv6 }
            return $0.id < $1.id
        }
    }
}
