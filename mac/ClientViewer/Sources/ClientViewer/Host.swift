//
//  Host.swift
//  ClientViewer
//
//  Model for a discovered ToInfinity Host on the LAN.
//
import Foundation
import Network

struct DiscoveredHost: Identifiable, Hashable {
    var id: String { hostID }
    let hostID: String
    let hostName: String
    let platform: String
    let controlPort: UInt16
    let address: NWEndpoint.Host
    let lastSeen: Date

    var displaySubtitle: String {
        "\(platform) · \(addressDescription)"
    }

    private var addressDescription: String {
        switch address {
        case .ipv4(let addr): return "\(addr)"
        case .ipv6(let addr): return "\(addr)"
        case .name(let name, _): return name
        @unknown default: return "unknown"
        }
    }
}
