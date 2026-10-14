//
//  File:      SSDSMARTDetails.swift
//  Created:   2026-10-15
//  Updated:   2026-10-15
//  Developer: SiliconScope contributors
//  Overview:  Compact device-reported SMART endurance and diagnostic values.
//  Notes:     Health is remaining rated endurance, never a failure prediction.
//
import SwiftUI
import SiliconScopeCore

struct SSDSMARTDetails: View {
    let samples: [SSDSMARTSample]?
    var body: some View {
        if let samples, !samples.isEmpty {
            ForEach(samples) { sample in
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(sample.deviceName ?? "SSD SMART").font(Theme.font(.caption)).foregroundStyle(Theme.faint)
                        .lineLimit(1).truncationMode(.middle)
                    row("Health · endurance", "\(sample.remainingEndurancePercent)%")
                        .help("NVMe SMART Percentage Used: \(sample.enduranceUsedPercent)% used. Remaining rated endurance = max(0, 100 − Percentage Used). A vendor estimate, not a failure prediction; 0% does not mean the drive has failed.")
                    row("Temperature", sample.temperatureCelsius.map { String(format: "%.0f°C", $0) } ?? "—")
                    row("Spare", sample.availableSparePercent.map { "\($0)%" } ?? "—")
                        .help("NVMe available spare capacity. Threshold: \(sample.spareThresholdPercent.map { "\($0)%" } ?? "—").")
                    row("Warnings", String(format: "0x%02X", sample.criticalWarning))
                        .help("NVMe critical-warning bitmask: bit 0 spare below threshold; 1 temperature; 2 reliability degraded; 3 read-only; 4 volatile-memory backup; 5 persistent-memory region. Zero means no active critical warnings, not 100% health.")
                    row("Media errors", sample.mediaErrors.map { String($0) } ?? "—")
                        .help("NVMe lifetime media and data-integrity error count.")
                }
            }
        } else {
            row("SSD health", "—").help("NVMe SMART unavailable. SATA and USB SMART are not queried.")
        }
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: Space.row) {
            Text(label).foregroundStyle(Theme.dim)
            Spacer(minLength: Space.hair)
            Text(value).monospacedDigit().foregroundStyle(Theme.text)
        }.font(Theme.font(.caption))
    }
}
