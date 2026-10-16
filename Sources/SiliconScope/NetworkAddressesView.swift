//
//  File:      NetworkAddressesView.swift
//  Created:   2026-10-15
//  Updated:   2026-10-16
//  Developer: SiliconScope contributors
//  Overview:  Snapshot interface rows with compact local addresses and expandable full details.
//  Notes:     Never samples live interfaces from a view, including during replay.
//
import SwiftUI
import SiliconScopeCore

struct NetworkAddressesView: View {
    let network: NetworkSample
    private var interfaces: [InterfaceStat] { Array(network.interfaces.prefix(NetworkSampler.maxInterfaceRows)) }
    private var otherAddresses: [NetworkAddress] {
        let shown = Set(interfaces.map(\.bsdName))
        return (network.localAddresses ?? []).filter { !shown.contains($0.interface) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            ForEach(interfaces) { iface in
                DisclosureGroup {
                    VStack(alignment: .trailing, spacing: Space.hair) {
                        Text("↓ \(formatRate(iface.downloadBytesPerSec))  ↑ \(formatRate(iface.uploadBytesPerSec))")
                            .foregroundStyle(Theme.dim)
                        addressDetails(network.addresses(for: iface.bsdName))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } label: {
                    HStack(spacing: Space.row) {
                        CompactDisclosureTitle(iface.name).lineLimit(1)
                        Text(network.addresses(for: iface.bsdName)?.first?.address ?? "—")
                            .foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .help("\(iface.bsdName) local addresses from getifaddrs. Default-route labels use SystemConfiguration. Expand for full copyable addresses and interface rates.")
            }
            if !otherAddresses.isEmpty {
                DisclosureGroup(interfaces.isEmpty ? "Addresses" : "More addresses") {
                    addressDetails(otherAddresses)
                }
                .help("Other interfaces reported by this snapshot, including VPN tunnels excluded from physical throughput totals.")
            } else if interfaces.isEmpty {
                HStack {
                    Text("Addresses").foregroundStyle(Theme.dim)
                    Spacer(minLength: Space.hair)
                    Text(network.localAddresses == nil ? "—" : "None reported").foregroundStyle(Theme.dim)
                }
            }
        }
        .font(Theme.font(.caption)).tint(Theme.dim)
        .disclosureGroupStyle(CompactDisclosureStyle())
    }
    private func addressDetails(_ addresses: [NetworkAddress]?) -> some View {
        VStack(alignment: .trailing, spacing: Space.hair) {
            if let addresses, !addresses.isEmpty {
                ForEach(addresses) { ip in
                    Text("\(ip.interface) · \(ip.isIPv6 ? "IPv6" : "IPv4")\(ip.isPrimary ? " · default route" : "")")
                        .foregroundStyle(Theme.faint)
                    Text(ip.address).foregroundStyle(Theme.text).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(addresses == nil ? "Addresses unavailable in this snapshot" : "No usable address reported")
                    .foregroundStyle(Theme.faint)
            }
        }
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
