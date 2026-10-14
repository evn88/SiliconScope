//
//  File:      PublicIPAddressStore.swift
//  Created:   2026-10-15
//  Updated:   2026-10-15
//  Developer: SiliconScope contributors
//  Overview:  Starts optional background public-IP reads without blocking metric sampling.
//  Notes:     Reads only after the explicitly named ipify option is enabled.
//
import Foundation
import SiliconScopeCore

@MainActor final class PublicIPAddressStore {
    private var cache = PublicIPCache()
    private var task: Task<Void, Never>?
    private var taskID: UUID?
    private var observedAt: Date?
    func update(enabled: Bool, demanded: Bool, network: inout NetworkSample) {
        let path = (network.localAddresses ?? []).filter(\.isPrimary).map(\.id).sorted().joined(separator: "|")
        let next = cache.update(enabled: enabled, demanded: demanded, path: path,
                                now: Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000)
        if taskID != cache.requestID { task?.cancel(); task = nil; taskID = nil }
        if let id = next {
            taskID = id
            task = Task { [weak self] in
                let address = await PublicIPClient.lookup()
                guard let self, !Task.isCancelled else { return }
                self.cache.finish(id, address: address)
                self.observedAt = self.cache.address == nil ? nil : Date()
                if self.taskID == id { self.task = nil; self.taskID = nil }
            }
        }
        if cache.address == nil { observedAt = nil }
        network.publicIPObservedAt = observedAt
        network.publicIPAddress = cache.address
        network.publicIPStatus = cache.status
    }
}
