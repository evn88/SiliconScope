//
//  File:      SSDCounterTests.swift
//  Created:   2026-10-15
//  Updated:   2026-10-15
//  Developer: SiliconScope contributors
//  Overview:  Counter provenance, reset, overflow and recording compatibility tests.
//  Notes:     Fixtures do not require storage hardware.
//
import XCTest
@testable import SiliconScopeCore

final class SSDCounterTests: XCTestCase {
    private func counter(_ read: UInt64? = 100, _ write: UInt64? = 200,
                         id: UInt64 = 1, atBoot: Bool = true) -> SSDCounter {
        SSDCounter(id: id, atBoot: atBoot, read: read, write: write)
    }
    func testFirstSampleIncludesTrafficBeforeAppLaunch() {
        var tracker = SSDCounterTracker()
        XCTAssertEqual(tracker.update([counter()])?.read, 100)
        XCTAssertEqual(tracker.update([counter(150, 250)])?.write, 250)
    }
    func testResetNeverBecomesNewBootTotal() {
        var tracker = SSDCounterTracker()
        _ = tracker.update([counter()])
        XCTAssertNil(tracker.update([counter(10, 20)]))
        XCTAssertNil(tracker.update([counter(300, 400)]))
    }
    func testMissingStatisticsAreUnknownAndRetainResetDetection() {
        var tracker = SSDCounterTracker()
        XCTAssertNil(tracker.update([]))
        _ = tracker.update([counter()])
        XCTAssertNil(tracker.update([counter(nil, nil)]))
        XCTAssertNil(tracker.update([counter(50, 60)]))
    }
    func testDeviceRemovalAndReplacementInvalidatesBootTotals() {
        for replacement in [[], [counter(id: 2)]] {
            var tracker = SSDCounterTracker()
            _ = tracker.update([counter()])
            XCTAssertNil(tracker.update(replacement))
            XCTAssertNil(tracker.update([counter()]))
        }
    }
    func testNotMatchedAtBootAndDuplicateDriversAreUnavailable() {
        var tracker = SSDCounterTracker()
        XCTAssertNil(tracker.update([counter(atBoot: false)]))
        var duplicate = SSDCounterTracker()
        XCTAssertNil(duplicate.update([counter(), counter()]))
    }
    func testSumOverflowAndZero() {
        XCTAssertNil(SSDCounterMath.sum([]))
        XCTAssertNil(SSDCounterMath.sum([UInt64.max, 1]))
        XCTAssertEqual(SSDCounterMath.sum([0, 0]), 0)
        var tracker = SSDCounterTracker()
        XCTAssertNil(tracker.update([counter(UInt64.max, 0), counter(1, 0, id: 2)]))
    }
    func testNVMeUnitsEndiannessUnknownAndOverflow() {
        var bytes = [UInt8](repeating: 0, count: 16)
        XCTAssertNil(SSDCounterMath.nvmeBytes(bytes))
        bytes[0] = 1; bytes[1] = 1
        XCTAssertEqual(SSDCounterMath.nvmeBytes(bytes), 257 * 512_000)
        bytes[8] = 1
        XCTAssertNil(SSDCounterMath.nvmeBytes(bytes))
        XCTAssertNil(SSDCounterMath.nvmeBytes([UInt8](repeating: 255, count: 16)))
        XCTAssertNil(SSDCounterMath.nvmeBytes([UInt8](repeating: 255, count: 8) + [UInt8](repeating: 0, count: 8)))
        XCTAssertNil(SSDCounterMath.nvmeBytes([1]))
    }
    func testOlderRecordingAndRoundTrip() throws {
        let old = Data(#"{"readBytesPerSec":1,"writeBytesPerSec":2,"totalBytes":100,"freeBytes":50}"#.utf8)
        var sample = try JSONDecoder().decode(DiskSample.self, from: old)
        XCTAssertNil(sample.ssdBootReadBytes)
        XCTAssertNil(sample.ssdLifetimeWriteBytes)
        sample.ssdBootReadBytes = 0
        sample.ssdLifetimeWriteBytes = 512_000
        sample.ssdSMART = [try XCTUnwrap(SSDSMARTSample.decode([UInt8](repeating: 0, count: 512), id: 1, name: "Fixture SSD"))]
        XCTAssertEqual(try JSONDecoder().decode(DiskSample.self, from: JSONEncoder().encode(sample)), sample)
    }
    func testSMARTHealthAndDiagnostics() throws {
        var log = [UInt8](repeating: 0, count: 512)
        log[1] = 0x2c; log[2] = 1 // 300 kelvin
        log[3] = 95; log[4] = 10; log[5] = 7; log[0] = 4
        log[160] = 2
        let sample = try XCTUnwrap(SSDSMARTSample.decode(log, id: 1))
        XCTAssertEqual(sample.remainingEndurancePercent, 93)
        XCTAssertEqual(try XCTUnwrap(sample.temperatureCelsius), 26.85, accuracy: 0.001)
        XCTAssertEqual(sample.availableSparePercent, 95)
        XCTAssertEqual(sample.spareThresholdPercent, 10)
        XCTAssertEqual(sample.criticalWarning, 4)
        XCTAssertEqual(sample.mediaErrors, 2)
        for used: UInt8 in [100, 101, 254, 255] {
            log[5] = used
            XCTAssertEqual(SSDSMARTSample.decode(log, id: 1)?.remainingEndurancePercent, 0)
        }
    }
    func testSMARTUnknownFieldsAndRealZeroes() throws {
        var log = [UInt8](repeating: 0, count: 512)
        let zero = try XCTUnwrap(SSDSMARTSample.decode(log, id: 1))
        XCTAssertEqual(zero.remainingEndurancePercent, 100)
        XCTAssertEqual(zero.mediaErrors, 0)
        XCTAssertEqual(zero.availableSparePercent, 0)
        XCTAssertNil(zero.temperatureCelsius)
        log[3] = 101; log[4] = 255; log[168] = 1
        log[1] = 255; log[2] = 255
        let unknown = try XCTUnwrap(SSDSMARTSample.decode(log, id: 1))
        XCTAssertNil(unknown.availableSparePercent)
        XCTAssertNil(unknown.spareThresholdPercent)
        XCTAssertNil(unknown.mediaErrors)
        XCTAssertNil(unknown.temperatureCelsius)
        XCTAssertNil(SSDSMARTSample.decode([], id: 1))
    }

    func testNoCriticalWarningProducesNoWarningText() throws {
        let sample = try XCTUnwrap(SSDSMARTSample.decode([UInt8](repeating: 0, count: 512), id: 1))
        XCTAssertTrue(sample.criticalWarnings.isEmpty)
    }
    func testCriticalWarningsKeepTheirIndividualMeanings() throws {
        var log = [UInt8](repeating: 0, count: 512)
        log[0] = 1 | 2 | 4 | 8 | 16 | 32 | 128
        let sample = try XCTUnwrap(SSDSMARTSample.decode(log, id: 1))
        XCTAssertEqual(sample.criticalWarnings, [
            "Spare capacity below threshold", "Temperature outside limits",
            "Device reliability degraded", "Drive is read-only", "Memory backup failed",
            "Persistent memory warning", "Other device warning"
        ])
        XCTAssertEqual(sample.remainingEndurancePercent, 100) // independent of warning bits
    }

}
