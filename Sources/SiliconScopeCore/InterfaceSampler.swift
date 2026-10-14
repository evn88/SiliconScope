//
//  File:      InterfaceSampler.swift
//  Created:   2026-06-19
//  Updated:   2026-10-15
//  Developer: Kennt Kim / Calida Lab
//  Overview:  Lists network interfaces (friendly name, BSD name, IPv4, connected) sudolessly
//             via SystemConfiguration (display names) + getifaddrs (addresses / up state).
//             Powers the Network menu-bar dropdown's interface list + "Not Connected".
//  Notes:     This sampler remains local only. Public-IP requests are separate and opt-in.
//             Connected includes usable IPv6-only interfaces. Per-process network I/O
//             is not obtainable sudolessly, so it is omitted.
//
import Foundation
import SystemConfiguration

public struct InterfaceInfo: Sendable, Identifiable, Equatable {
    public let name: String        // friendly, e.g. "Wi-Fi"
    public let bsdName: String     // e.g. "en0"
    public let ipv4: String?
    public let isConnected: Bool
    public var id: String { bsdName }
}

public enum InterfaceSampler {
    public static func sample() -> [InterfaceInfo] {
        // Friendly display names keyed by BSD name.
        var friendly: [String: String] = [:]
        if let list = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for iface in list {
                if let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
                   let disp = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? {
                    friendly[bsd] = disp
                }
            }
        }

        // IPv4 addresses + running state from getifaddrs.
        var ipByBSD: [String: String] = [:]
        var running: Set<String> = []
        var addressed: Set<String> = []
        var head: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&head) == 0 {
            var cur = head
            while let p = cur {
                let ifa = p.pointee
                let bsd = String(cString: ifa.ifa_name)
                if (ifa.ifa_flags & UInt32(IFF_UP)) != 0 && (ifa.ifa_flags & UInt32(IFF_RUNNING)) != 0 {
                    running.insert(bsd)
                }
                if let addr = ifa.ifa_addr,
                   addr.pointee.sa_family == UInt8(AF_INET) || addr.pointee.sa_family == UInt8(AF_INET6) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let value = String(cBuffer: host)
                        if IPAddress.usableLocal(value) {
                            addressed.insert(bsd)
                            if addr.pointee.sa_family == UInt8(AF_INET) { ipByBSD[bsd] = value }
                        }
                    }
                }
                cur = ifa.ifa_next
            }
            freeifaddrs(head)
        }

        let out = friendly.map { bsd, disp -> InterfaceInfo in
            let ip = ipByBSD[bsd]
            return InterfaceInfo(name: disp, bsdName: bsd, ipv4: ip,
                                 isConnected: addressed.contains(bsd) && running.contains(bsd))
        }
        // Connected first, then by name.
        return out.sorted { ($0.isConnected ? 0 : 1, $0.name) < ($1.isConnected ? 0 : 1, $1.name) }
    }
}
