//
//  File:      NetworkAddressTests.swift
//  Created:   2026-10-15
//  Updated:   2026-10-16
//  Developer: SiliconScope contributors
//  Overview:  Local address filtering, BSD association and recording compatibility fixtures.
//  Notes:     Documentation addresses only; no network requests or user address logging.
//
import XCTest
import Darwin
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
    func testAddressesAreAssociatedByBSDInterfaceNotGlobalPrimary() {
        var sample = NetworkSample()
        let wifi = NetworkAddress(interface: "en0", address: "192.0.2.10", isIPv6: false, isPrimary: false)
        let ethernet = NetworkAddress(interface: "en7", address: "2001:db8::7", isIPv6: true, isPrimary: false)
        let tunnel = NetworkAddress(interface: "utun3", address: "2001:db8::3", isIPv6: true, isPrimary: true)
        sample.localAddresses = [tunnel, ethernet, wifi]
        XCTAssertEqual(sample.addresses(for: "en0"), [wifi])
        XCTAssertEqual(sample.addresses(for: "en7"), [ethernet])
        XCTAssertEqual(sample.addresses(for: "utun3"), [tunnel])
        XCTAssertEqual(sample.addresses(for: "en99"), [])
    }
    func testMissingAndEmptyAddressSnapshotsRemainDistinct() throws {
        var sample = try JSONDecoder().decode(NetworkSample.self, from: Data("{}".utf8))
        XCTAssertNil(sample.addresses(for: "en0"))
        sample.localAddresses = []
        XCTAssertEqual(sample.addresses(for: "en0"), [])
        XCTAssertEqual(try JSONDecoder().decode(NetworkSample.self, from: JSONEncoder().encode(sample)), sample)
    }
    func testOldPublicFieldsAreIgnoredAndNotReencoded() throws {
        let json = #"{"publicIPAddress":"198.51.100.9","publicIPStatus":"available","publicIPObservedAt":123,"interfaces":[{"name":"Wi-Fi","bsdName":"en0","downloadBytesPerSec":1,"uploadBytesPerSec":2}]}"#
        let sample = try JSONDecoder().decode(NetworkSample.self, from: Data(json.utf8))
        XCTAssertEqual(sample.interfaces.first?.bsdName, "en0")
        XCTAssertNil(sample.addresses(for: "en0"))
        let encoded = try JSONEncoder().encode(sample)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["publicIPAddress"])
        XCTAssertNil(object["publicIPStatus"])
        XCTAssertNil(object["publicIPObservedAt"])
    }
    func testLocalAddressRoundTripPreservesLongIPv6AndTunnels() throws {
        var sample = NetworkSample()
        sample.localAddresses = [NetworkAddress(interface: "utun3", address: "2001:db8:1234:5678:90ab:cdef:1234:5678", isIPv6: true, isPrimary: true)]
        XCTAssertEqual(try JSONDecoder().decode(NetworkSample.self, from: JSONEncoder().encode(sample)), sample)
    }
    func testIPv6OnlyRunningTunnelAddressFromSharedScan() {
        var socket = sockaddr_in6()
        socket.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        socket.sin6_family = sa_family_t(AF_INET6)
        XCTAssertEqual(inet_pton(AF_INET6, "2001:db8::3", &socket.sin6_addr), 1)
        "utun3".withCString { name in
            withUnsafeMutablePointer(to: &socket) { pointer in
                var entry = ifaddrs()
                entry.ifa_name = UnsafeMutablePointer(mutating: name)
                entry.ifa_flags = UInt32(IFF_UP | IFF_RUNNING)
                entry.ifa_addr = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: sockaddr.self)
                let address = NetworkAddressSampler.address(entry, primaryIPv4: "en0", primaryIPv6: "utun3")
                XCTAssertEqual(address?.interface, "utun3")
                XCTAssertEqual(address?.address, "2001:db8::3")
                XCTAssertEqual(address?.isPrimary, true)
                entry.ifa_flags = UInt32(IFF_UP)
                XCTAssertNil(NetworkAddressSampler.address(entry, primaryIPv4: nil, primaryIPv6: "utun3"))
            }
        }
    }
}
