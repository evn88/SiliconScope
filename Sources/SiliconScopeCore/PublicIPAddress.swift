//
//  File:      PublicIPAddress.swift
//  Created:   2026-10-15
//  Updated:   2026-10-15
//  Developer: SiliconScope contributors
//  Overview:  Opt-in ipify client and pure cache/request policy.
//  Notes:     No requests from initialization. Call only after the named-service opt-in.
//
import Foundation

public enum PublicIPStatus: String, Sendable, Codable { case off, checking, unavailable, available }

public struct PublicIPCache: Sendable {
    public private(set) var address: String?
    public private(set) var status: PublicIPStatus = .off
    public private(set) var requestID: UUID?
    private var path: String?
    private var lastAttempt: TimeInterval?
    private var pendingPathRefresh = true
    public init() {}

    /// Stable routes refresh at 10 minutes; changed routes wait at least 60 seconds between requests.
    /// A changed/unknown route, disabled option or lost demand clears the old result immediately.
    public mutating func update(enabled: Bool, demanded: Bool, path newPath: String,
                                now: TimeInterval) -> UUID? {
        guard enabled, demanded, !newPath.isEmpty else {
            path = nil; requestID = nil; address = nil; pendingPathRefresh = true
            status = enabled ? .unavailable : .off
            return nil
        }
        if path != newPath {
            path = newPath; requestID = nil; address = nil
            pendingPathRefresh = true; status = .unavailable
        }
        guard requestID == nil else { return nil }
        let interval: TimeInterval = pendingPathRefresh ? 60 : 600
        if let lastAttempt, now - lastAttempt < interval { return nil }
        address = nil; status = .checking; lastAttempt = now; pendingPathRefresh = false
        let id = UUID(); requestID = id
        return id
    }
    public mutating func finish(_ id: UUID, address: String?) {
        guard requestID == id else { return }
        requestID = nil
        self.address = address.flatMap { IPAddress.family($0) != nil ? $0 : nil }
        status = self.address == nil ? .unavailable : .available
    }
}

private final class PublicIPRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

public enum PublicIPClient {
    public static let serviceName = "ipify"
    public static let endpoint = URL(string: "https://api64.ipify.org?format=json")!
    public static func decode(_ data: Data, statusCode: Int) -> String? {
        struct Reply: Decodable { let ip: String }
        guard statusCode == 200, data.count <= 4096,
              let reply = try? JSONDecoder().decode(Reply.self, from: data),
              IPAddress.family(reply.ip) != nil else { return nil }
        return reply.ip
    }
    public static func lookup() async -> String? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: PublicIPRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              !Task.isCancelled, let http = response as? HTTPURLResponse else { return nil }
        return decode(data, statusCode: http.statusCode)
    }
}
