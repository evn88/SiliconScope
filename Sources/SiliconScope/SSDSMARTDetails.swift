//
//  File:      SSDSMARTDetails.swift
//  Created:   2026-10-15
//  Updated:   2026-10-15
//  Developer: SiliconScope contributors
//  Overview:  Compact SSD health line with optional SMART details.
//  Notes:     Health is remaining rated endurance, never a failure prediction.
//
import SwiftUI
import SiliconScopeCore

struct SSDSMARTDetails: View {
    let samples: [SSDSMARTSample]?
    var body: some View {
        if let samples, !samples.isEmpty {
            ForEach(samples) { sample in
                SSDSMARTDeviceDetails(sample: sample, showName: samples.count > 1)
            }
        } else {
            smartRow("SSD health", "—")
                .help("NVMe SMART unavailable. SATA and USB SMART are not queried.")
        }
    }
}

private struct SSDSMARTDeviceDetails: View {
    let sample: SSDSMARTSample
    let showName: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Space.hair) {
                    if !showName {
                        Text(sample.deviceName ?? "SSD SMART").foregroundStyle(Theme.faint)
                    }
                    smartRow("Endurance used", "\(sample.enduranceUsedPercent)%")
                    smartRow("Temperature", sample.temperatureCelsius.map { String(format: "%.0f°C", $0) } ?? "—")
                    smartRow("Spare capacity", sample.availableSparePercent.map { "\($0)%" } ?? "—")
                    smartRow("Spare threshold", sample.spareThresholdPercent.map { "\($0)%" } ?? "—")
                    smartRow("Data integrity errors", sample.mediaErrors.map { String($0) } ?? "—")
                        .help("NVMe lifetime count of unrecovered media and data integrity errors (including ECC, CRC and LBA tag errors). Separate from OS read/write errors; no counters are combined.")
                }.padding(.top, Space.hair)
            } label: {
                smartRow(showName ? (sample.deviceName ?? "SSD health") : "SSD health",
                         "\(sample.remainingEndurancePercent)% endurance")
            }
            .help("Remaining rated endurance = max(0, 100 − NVMe Percentage Used). A vendor estimate, not a failure prediction; 0% does not mean the drive has failed. Expand for SMART details.")
            .tint(Theme.dim)
            ForEach(sample.criticalWarnings, id: \.self) { warning in
                Text(warning).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
        }.font(Theme.font(.caption))
    }
}

private func smartRow(_ label: String, _ value: String) -> some View {
    HStack(spacing: Space.row) {
        Text(label).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.middle)
        Spacer(minLength: Space.hair)
        Text(value).monospacedDigit().foregroundStyle(Theme.text)
    }.font(Theme.font(.caption))
}
