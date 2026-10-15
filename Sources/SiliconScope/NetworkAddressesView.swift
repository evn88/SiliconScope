//
//  File:      NetworkAddressesView.swift
//  Created:   2026-10-15
//  Updated:   2026-10-15
//  Developer: SiliconScope contributors
//  Overview:  Compact local/public addresses with copyable full IPv6/interface details.
//  Notes:     Displays snapshot data only; never starts a lookup from a view.
//
import SwiftUI
import SiliconScopeCore

struct NetworkAddressesView: View {
    let network: NetworkSample
    var body: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            DisclosureGroup {
                VStack(alignment: .trailing, spacing: Space.hair) {
                    if let addresses = network.localAddresses, !addresses.isEmpty {
                        ForEach(addresses) { ip in
                            VStack(alignment: .trailing, spacing: Space.hair) {
                                Text("\(ip.interface) · \(ip.isIPv6 ? "IPv6" : "IPv4")\(ip.isPrimary ? " · default route" : "")")
                                    .foregroundStyle(Theme.faint)
                                Text(ip.address).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else { Text("No usable local address reported").foregroundStyle(Theme.faint) }
                    if let ip = network.publicIPAddress {
                        Text("Public IP · ipify").foregroundStyle(Theme.faint)
                        if let checked = network.publicIPObservedAt {
                            Text("Checked \(checked.formatted(date: .omitted, time: .standard))")
                                .foregroundStyle(Theme.faint)
                        }
                        Text(ip).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
            } label: {
                addressRow("Local IP", (network.localAddresses ?? []).first(where: \.isPrimary)?.address ?? "—")
            }.tint(Theme.dim)
            addressRow("Public IP", publicValue)
                .help("Optional ipify lookup, off by default. This is the address ipify sees on its current connection, which may be a VPN exit. Split tunneling and IPv4/IPv6 routes can have other exit addresses. Expand Local IP to read/copy full addresses.")
        }.font(Theme.font(.caption))
    }
    private var publicValue: String {
        switch network.publicIPStatus {
        case .off: return "Off"
        case .checking: return "Checking…"
        case .available: return network.publicIPAddress ?? "—"
        case .unavailable, nil: return "—"
        }
    }
    private func addressRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: Space.row) {
            Text(label).foregroundStyle(Theme.dim).fixedSize(horizontal: true, vertical: false)
            Text(value).foregroundStyle(Theme.text).lineLimit(value.contains(":") ? nil : 1)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .help(value)
        }
    }
}
