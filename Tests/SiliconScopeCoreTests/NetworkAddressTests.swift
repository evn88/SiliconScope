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
    func testTunnelChangesInvalidateCacheWithoutChangingPrimaryInterface() {
        let physical = NetworkAddress(interface: "en0", address: "192.0.2.2", isIPv6: false, isPrimary: true)
        let tunnel = NetworkAddress(interface: "utun3", address: "10.0.0.2", isIPv6: false, isPrimary: false)
        XCTAssertNotEqual(NetworkAddressSampler.routeFingerprint([physical]),
                          NetworkAddressSampler.routeFingerprint([physical, tunnel]))
        XCTAssertEqual(NetworkAddressSampler.routeFingerprint([tunnel, physical]),
                       NetworkAddressSampler.routeFingerprint([physical, tunnel]))
        XCTAssertEqual(NetworkAddressSampler.routeFingerprint([tunnel]), "")
        XCTAssertEqual(NetworkAddressSampler.routeFingerprint(nil), "")
    }

    func testRepeatedSamplingKeepsCachedAddressUntilTenMinuteRefresh() throws {
        var cache = PublicIPCache()
        let first = try XCTUnwrap(cache.update(enabled: true, demanded: true, path: "en0", now: 0))
        cache.finish(first, address: "198.51.100.9")
        for tick in 1..<600 {
            XCTAssertNil(cache.update(enabled: true, demanded: true, path: "en0", now: Double(tick)))
            XCTAssertEqual(cache.address, "198.51.100.9")
            XCTAssertEqual(cache.status, .available)
        }
        XCTAssertNotNil(cache.update(enabled: true, demanded: true, path: "en0", now: 600))
    }

    func testRepeatedFailuresBackOffForTenMinutes() {
        var cache = PublicIPCache()
        var attempts: [Int] = []
        for tick in 0...1800 {
            if let id = cache.update(enabled: true, demanded: true, path: "en0", now: Double(tick)) {
                attempts.append(tick)
                cache.finish(id, address: nil)
            }
        }
        XCTAssertEqual(attempts, [0, 600, 1200, 1800])
    }

    func testRouteFlappingIsLimitedToOneAttemptPerMinute() {
        var cache = PublicIPCache()
        var attempts: [Int] = []
        for tick in 0...180 {
            let route = tick.isMultiple(of: 2) ? "en0" : "utun3"
            if let id = cache.update(enabled: true, demanded: true, path: route, now: Double(tick)) {
                attempts.append(tick)
                cache.finish(id, address: nil)
            }
        }
        XCTAssertEqual(attempts, [0, 60, 120, 180])
    }

    func testLostDemandDiscardsInFlightResultAndKeepsCooldown() throws {
        var cache = PublicIPCache()
        let id = try XCTUnwrap(cache.update(enabled: true, demanded: true, path: "en0", now: 0))
        XCTAssertNil(cache.update(enabled: true, demanded: false, path: "en0", now: 1))
        XCTAssertNil(cache.requestID)
        cache.finish(id, address: "198.51.100.9")
        XCTAssertNil(cache.address)
        XCTAssertNil(cache.update(enabled: true, demanded: true, path: "en0", now: 59))
        XCTAssertNotNil(cache.update(enabled: true, demanded: true, path: "en0", now: 60))
    }

    func testClientUsesMockTransportWithoutExternalLookup() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockIPProtocol.self]
        let result = await PublicIPClient.lookup(configuration: configuration)
        XCTAssertEqual(result, "198.51.100.9")
    }

}


private final class MockIPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url == PublicIPClient.endpoint else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let response = HTTPURLResponse(url: PublicIPClient.endpoint, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"ip":"198.51.100.9"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
