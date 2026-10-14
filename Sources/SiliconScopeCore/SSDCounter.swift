//
//  File:      SSDCounter.swift
//  Created:   2026-10-15
//  Updated:   2026-10-15
//  Developer: SiliconScope contributors
//  Overview:  Validate internal SSD driver totals and decode NVMe host data units.
//  Notes:     Driver counters start at driver initialization, not app launch.
//
import Foundation

struct SSDCounter: Equatable {
    var id: UInt64
    var atBoot: Bool
    var read: UInt64?
    var write: UInt64?
}

enum SSDCounterMath {
    static func sum(_ values: [UInt64]) -> UInt64? {
        guard !values.isEmpty else { return nil }
        var total: UInt64 = 0
        for value in values {
            let addition = total.addingReportingOverflow(value)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }
        return total
    }

    static func uint128(_ bytes: [UInt8]) -> UInt64? {
        guard bytes.count == 16, bytes[8...].allSatisfy({ $0 == 0 }) else { return nil }
        return bytes.prefix(8).enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
    }

    /// NVMe SMART 128-bit little-endian data units, each 1000 * 512 bytes.
    /// Units are rounded up by the device; zero means not reported per NVMe.
    /// Reject values that cannot be represented, never truncate or saturate them.
    static func nvmeBytes(_ bytes: [UInt8]) -> UInt64? {
        guard let units = uint128(bytes) else { return nil }
        let value = units.multipliedReportingOverflow(by: 512_000)
        return units > 0 && !value.overflow ? value.partialValue : nil
    }
}

struct SSDCounterTracker {
    private var previous: [UInt64: SSDCounter] = [:]
    private var initialIDs: Set<UInt64>?
    private var invalidated = false

    mutating func update(_ counters: [SSDCounter]) -> (read: UInt64, write: UInt64)? {
        let ids = Set(counters.map(\.id))
        if initialIDs == nil, !ids.isEmpty { initialIDs = ids }
        if let initialIDs, initialIDs != ids { invalidated = true }
        for counter in counters {
            if let old = previous[counter.id],
               let oldRead = old.read, let oldWrite = old.write,
               let read = counter.read, let write = counter.write,
               (read < oldRead || write < oldWrite) { invalidated = true }
        }
        // Keep the last known counters through a temporarily missing statistic.
        for counter in counters where counter.read != nil && counter.write != nil { previous[counter.id] = counter }
        guard !invalidated, !counters.isEmpty, ids.count == counters.count,
              counters.allSatisfy({ $0.atBoot && $0.read != nil && $0.write != nil }),
              let read = SSDCounterMath.sum(counters.compactMap(\.read)),
              let write = SSDCounterMath.sum(counters.compactMap(\.write)) else { return nil }
        return (read, write)
    }
}

/// Device-reported NVMe SMART values, independent of the OS boot counters.
public struct SSDSMARTSample: Sendable, Equatable, Codable, Identifiable {
    public var id: UInt64
    public var deviceName: String?
    public var enduranceUsedPercent: UInt8
    public var temperatureCelsius: Double?
    public var availableSparePercent: UInt8?
    public var spareThresholdPercent: UInt8?
    public var criticalWarning: UInt8
    public var mediaErrors: UInt64?

    /// Remaining rated endurance, not a prediction of failure or a SMART pass score.
    public var remainingEndurancePercent: Int { max(0, 100 - Int(enduranceUsedPercent)) }

    /// Each reported NVMe warning bit has its own meaning; do not fold them into a health score.
    public var criticalWarnings: [String] {
        let meanings: [(UInt8, String)] = [
            (1, "Spare capacity below threshold"),
            (2, "Temperature outside limits"),
            (4, "Device reliability degraded"),
            (8, "Drive is read-only"),
            (16, "Memory backup failed"),
            (32, "Persistent memory warning")
        ]
        var warnings = meanings.filter { criticalWarning & $0.0 != 0 }.map { $0.1 }
        if criticalWarning & 0xC0 != 0 { warnings.append("Other device warning") }
        return warnings
    }

    static func decode(_ log: [UInt8], id: UInt64, name: String? = nil) -> SSDSMARTSample? {
        guard log.count == 512 else { return nil }
        let kelvin = UInt16(log[1]) | UInt16(log[2]) << 8
        return SSDSMARTSample(id: id, deviceName: name, enduranceUsedPercent: log[5],
            temperatureCelsius: kelvin == 0 || kelvin == UInt16.max ? nil : Double(kelvin) - 273.15,
            availableSparePercent: log[3] <= 100 ? log[3] : nil,
            spareThresholdPercent: log[4] <= 100 ? log[4] : nil,
            criticalWarning: log[0], mediaErrors: SSDCounterMath.uint128(Array(log[160..<176])))
    }
}
