//
//  File:      Disk.swift
//  Created:   2026-06-08
//  Updated:   2026-10-15
//  Developer: Kennt Kim / Calida Lab
//  Overview:  Disk I/O throughput (read/write bytes per second) and boot-volume
//             capacity, sampled sudolessly. I/O via IOBlockStorageDriver statistics
//             (stateful diff); capacity via volume resource values.
//  Notes:     Sums "Bytes (Read)"/"Bytes (Write)" across all block storage drivers.
//             New SSD totals include only internal solid-state boot-matched drivers.
//             NVMe SMART is read every 30 s; unsupported devices remain unknown.
//             freeBytes uses AvailableCapacityForImportantUsage (purgeable-aware).
//
import Foundation
import IOKit
import CIOReport

public struct DiskSample: Sendable, Equatable, Codable {
    public var readBytesPerSec: Double = 0
    public var writeBytesPerSec: Double = 0
    public var totalBytes: UInt64 = 0
    public var freeBytes: UInt64 = 0

    /// Internal SSD host I/O counters; nil means unavailable (including old recordings).
    public var ssdBootReadBytes: UInt64?
    public var ssdBootWriteBytes: UInt64?
    public var ssdLifetimeReadBytes: UInt64?
    public var ssdLifetimeWriteBytes: UInt64?
    public var ssdSMART: [SSDSMARTSample]?

    public init() {}

    private static let gb = 1024.0 * 1024.0 * 1024.0
    public var totalGB: Double { Double(totalBytes) / Self.gb }
    public var freeGB: Double { Double(freeBytes) / Self.gb }
    public var usedFraction: Double {
        totalBytes > 0 ? Double(totalBytes - min(freeBytes, totalBytes)) / Double(totalBytes) : 0
    }
}

public final class DiskSampler {
    private var ssdTracker = SSDCounterTracker()
    private var cachedSMART: [SSDSMARTSample]?
    private var cachedLifetime: (UInt64?, UInt64?) = (nil, nil)
    private var lifetimeIDs = Set<UInt64>()
    private var lastSMARTSampleNs: UInt64 = 0
    private var previousRead: UInt64 = 0
    private var previousWrite: UInt64 = 0
    private var previousTimeNs: UInt64 = 0

    // Capacity on a slow cadence: querying volumeAvailableCapacityForImportantUsage triggers
    // Apple's CacheDelete framework to re-validate EVERY mounted volume's purgeable space
    // (getattrlist/realpath/APFS-role IOKit storm on in-process queues — profiled at ~4% of a
    // core when run each tick). Free space doesn't change per-second; 30 s is plenty.
    // (docs/energy-optimization.md — closed-window cost investigation.)
    private var cachedCapacity: (total: UInt64, free: UInt64) = (0, 0)
    private var lastCapacitySample: Date = .distantPast
    private let capacityInterval: TimeInterval = 30

    public init() {}

    public func sample() -> DiskSample {
        var result = DiskSample()

        let (read, write) = Self.ioBytes()
        let devices = Self.internalSSDs()
        let boot = ssdTracker.update(devices.map { $0.counter })
        result.ssdBootReadBytes = boot?.read
        result.ssdBootWriteBytes = boot?.write
        let ids = Set(devices.map { $0.counter.id })
        if ids != lifetimeIDs {
            cachedLifetime = (nil, nil)
            cachedSMART = nil
            lastSMARTSampleNs = 0
            lifetimeIDs = ids
        }
        let smartNow = DispatchTime.now().uptimeNanoseconds
        if lastSMARTSampleNs == 0 || smartNow - lastSMARTSampleNs >= 30_000_000_000 {
            lastSMARTSampleNs = smartNow
            let smart = Self.lifetimeBytes(devices)
            cachedLifetime = (smart.0, smart.1)
            cachedSMART = smart.2
        }
        result.ssdLifetimeReadBytes = cachedLifetime.0
        result.ssdLifetimeWriteBytes = cachedLifetime.1
        result.ssdSMART = cachedSMART
        for device in devices { IOObjectRelease(device.service) }
        let now = DispatchTime.now().uptimeNanoseconds
        if previousTimeNs > 0 {
            let seconds = Double(now &- previousTimeNs) / 1_000_000_000
            if seconds > 0 {
                result.readBytesPerSec = Double(read >= previousRead ? read - previousRead : 0) / seconds
                result.writeBytesPerSec = Double(write >= previousWrite ? write - previousWrite : 0) / seconds
            }
        }
        previousRead = read
        previousWrite = write
        previousTimeNs = now

        if Date().timeIntervalSince(lastCapacitySample) >= capacityInterval {
            lastCapacitySample = Date()
            cachedCapacity = Self.capacity()
        }
        result.totalBytes = cachedCapacity.total
        result.freeBytes = cachedCapacity.free
        return result
    }

    private static func capacity() -> (UInt64, UInt64) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return (0, 0) }
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        return (total, free)
    }

    private static func ioBytes() -> (UInt64, UInt64) {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = properties?.takeRetainedValue() as NSDictionary?,
               let stats = dict["Statistics"] as? NSDictionary {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return (read, write)
    }

    private struct SSDDevice {
        var service: io_service_t
        var name: String?
        var counter: SSDCounter
    }

    private static func internalSSDs() -> [SSDDevice] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var devices: [SSDDevice] = []
        var driver = IOIteratorNext(iterator)
        while driver != IO_OBJECT_NULL {
            defer { IOObjectRelease(driver); driver = IOIteratorNext(iterator) }
            var parent = io_registry_entry_t()
            guard IORegistryEntryGetParentEntry(driver, kIOServicePlane, &parent) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(parent) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(parent, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as NSDictionary?,
                  let device = dict["Device Characteristics"] as? NSDictionary,
                  device["Medium Type"] as? String == "Solid State",
                  let proto = dict["Protocol Characteristics"] as? NSDictionary,
                  proto["Physical Interconnect Location"] as? String == "Internal" else { continue }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(driver, &id) == KERN_SUCCESS else { continue }
            let atBoot = IORegistryEntryCreateCFProperty(driver, "IOMatchedAtBoot" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool == true
            let stats = IORegistryEntryCreateCFProperty(driver, "Statistics" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSDictionary
            IOObjectRetain(parent)
            devices.append(SSDDevice(service: parent, name: device["Product Name"] as? String, counter: SSDCounter(id: id, atBoot: atBoot,
                read: (stats?["Bytes (Read)"] as? NSNumber)?.uint64Value,
                write: (stats?["Bytes (Write)"] as? NSNumber)?.uint64Value)))
        }
        return devices
    }

    private static func lifetimeBytes(_ devices: [SSDDevice]) -> (UInt64?, UInt64?, [SSDSMARTSample]?) {
        guard !devices.isEmpty else { return (nil, nil, nil) }
        var reads: [UInt64] = [], writes: [UInt64] = []
        var samples: [SSDSMARTSample] = []
        for device in devices {
            guard IORegistryEntryCreateCFProperty(device.service, "NVMe SMART Capable" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool == true else { continue }
            var log = [UInt8](repeating: 0, count: 512)
            guard log.withUnsafeMutableBufferPointer({ sscope_nvme_smart(device.service, $0.baseAddress!) }) else {
                continue
            }
            if let sample = SSDSMARTSample.decode(log, id: device.counter.id, name: device.name) { samples.append(sample) }
            if let read = SSDCounterMath.nvmeBytes(Array(log[32..<48])) { reads.append(read) }
            if let write = SSDCounterMath.nvmeBytes(Array(log[48..<64])) { writes.append(write) }
        }
        return (reads.count == devices.count ? SSDCounterMath.sum(reads) : nil,
                writes.count == devices.count ? SSDCounterMath.sum(writes) : nil,
                samples.isEmpty ? nil : samples.sorted { $0.id < $1.id })
    }

}
