//
//  File:      NetworkAddressTests.swift
//  Created:   2026-10-15
//  Updated:   2026-10-15
//  Developer: SiliconScope contributors
//  Overview:  Address selection, compatibility and opt-in public-IP policy fixtures.
//  Notes:     Documentation addresses only; no external requests or user IP logging.
//
import XCTest
@testable import SiliconScopeCore

final class NetworkAddressTests: XCTestCase {
    func testAddressParsingAndLocalFiltering() {
        XCTAssertNotNil(IPAddress.family("192.0.2.10"))
        XCTAssertNotNil(IPAddress.family("2001:db8::1234"))
        for value in ["", "https://example.org", "1.2.3.999", "1.2.3.4\n", "fe80::1%en0"] {
            XCTAssertNil(IPAddress.family(value))
        }
        for value in ["127.0.0.1", "0.0.0.0", "169.254.1.1", "224.0.0.1", "::", "::1", "fe80::1", "ff02::1"] {
            XCTAssertFalse(IPAddress.usableLocal(value))
        }
        XCTAssertTrue(IPAddress.usableLocal("10.0.0.2"))
        XCTAssertTrue(IPAddress.usableLocal("fd00::2"))
    }
    func testVPNDefaultAndDifferentFamilyRoutesComeFirst() {
        let physical = NetworkAddress(interface: "en0", address: "192.0.2.2", isIPv6: false, isPrimary: false)
        let vpn = NetworkAddress(interface: "utun3", address: "10.0.0.2", isIPv6: false, isPrimary: true)
        let ipv6 = NetworkAddress(interface: "en0", address: "2001:db8::2", isIPv6: true, isPrimary: true)
        XCTAssertEqual(NetworkAddressSampler.ordered([physical, ipv6, vpn, vpn]), [vpn, ipv6, physical])
    }
    func testOlderRecordingAndAddressRoundTrip() throws {
        var network = try JSONDecoder().decode(NetworkSample.self, from: Data("{}".utf8))
        XCTAssertNil(network.localAddresses)
        XCTAssertNil(network.publicIPStatus)
        network.localAddresses = []
        network.publicIPStatus = .off
        network.publicIPObservedAt = Date(timeIntervalSince1970: 123)
        XCTAssertEqual(try JSONDecoder().decode(NetworkSample.self, from: JSONEncoder().encode(network)), network)
    }
    func testPublicResponseIPv4IPv6AndInvalidPayloads() {
        for ip in ["198.51.100.9", "2001:db8::9"] {
            XCTAssertEqual(PublicIPClient.decode(Data("{\"ip\":\"\(ip)\"}".utf8), statusCode: 200), ip)
        }
        for text in ["<html>captive portal</html>", "{}", "{\"ip\":\"bad\"}", "{\"ip\":\"198.51.100.9\\n\"}"] {
            XCTAssertNil(PublicIPClient.decode(Data(text.utf8), statusCode: 200))
        }
        XCTAssertNil(PublicIPClient.decode(Data("{\"ip\":\"198.51.100.9\"}".utf8), statusCode: 503))
        XCTAssertNil(PublicIPClient.decode(Data(repeating: 0, count: 4097), statusCode: 200))
    }
    func testDisabledOfflineAndNoDemandNeverRequest() {
        var cache = PublicIPCache()
        XCTAssertNil(cache.update(enabled: false, demanded: true, path: "en0", now: 0))
        XCTAssertEqual(cache.status, .off)
        XCTAssertNil(cache.update(enabled: true, demanded: true, path: "", now: 0))
        XCTAssertNil(cache.update(enabled: true, demanded: false, path: "en0", now: 0))
        XCTAssertNil(cache.address)
    }
    func testStableRefreshIsTenMinutesAndDoesNotOverlap() throws {
        var cache = PublicIPCache()
        let id = try XCTUnwrap(cache.update(enabled: true, demanded: true, path: "en0", now: 0))
        XCTAssertNil(cache.update(enabled: true, demanded: true, path: "en0", now: 600))
        cache.finish(id, address: "198.51.100.9")
        XCTAssertEqual(cache.address, "198.51.100.9")
        XCTAssertNil(cache.update(enabled: true, demanded: true, path: "en0", now: 599))
        XCTAssertNotNil(cache.update(enabled: true, demanded: true, path: "en0", now: 600))
        XCTAssertNil(cache.address)
    }
    func testRouteChangeClearsResultAndDiscardsLateResponse() throws {
        var cache = PublicIPCache()
        let old = try XCTUnwrap(cache.update(enabled: true, demanded: true, path: "en0", now: 0))
        XCTAssertNil(cache.update(enabled: true, demanded: true, path: "utun3", now: 1))
        cache.finish(old, address: "198.51.100.9")
        XCTAssertNil(cache.address)
        XCTAssertNotNil(cache.update(enabled: true, demanded: true, path: "utun3", now: 60))
    }
    func testFailureAndOptOutNeverRetainAnAddress() throws {
        var cache = PublicIPCache()
        let id = try XCTUnwrap(cache.update(enabled: true, demanded: true, path: "en0", now: 0))
        cache.finish(id, address: nil)
        XCTAssertEqual(cache.status, .unavailable)
        XCTAssertNil(cache.update(enabled: true, demanded: true, path: "en0", now: 599))
        let next = try XCTUnwrap(cache.update(enabled: true, demanded: true, path: "en0", now: 600))
        _ = cache.update(enabled: false, demanded: true, path: "en0", now: 601)
        cache.finish(next, address: "198.51.100.9")
        XCTAssertNil(cache.address)
        XCTAssertEqual(cache.status, .off)
    }
}
