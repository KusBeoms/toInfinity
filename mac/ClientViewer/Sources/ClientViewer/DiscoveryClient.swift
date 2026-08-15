//
//  DiscoveryClient.swift
//  ClientViewer
//
//  Sends periodic UDP "query" discovery datagrams (SPEC.md §1.2) and
//  collects unicast "announce" replies from HostAgents on the LAN.
//
//  Network.framework detail: a UDP `NWConnection` constructed with a
//  specific remote endpoint behaves like a connected socket and will only
//  deliver datagrams back from that exact remote endpoint. Since each
//  HostAgent replies *unicast* from its own address (not from the
//  broadcast address we sent to), we can't receive those replies on the
//  same connection we broadcast from. Instead we mirror HostAgent's own
//  design: an `NWListener` bound to a known local UDP port receives each
//  reply as its own inbound "connection" (one per sender), and a separate
//  connection — explicitly bound to that same local port — sends the
//  outgoing broadcast probe.
//
import Foundation
import ToInfinityProtocol
import Network

@MainActor
final class DiscoveryClient: ObservableObject {
    @Published private(set) var hosts: [DiscoveredHost] = []

    private var listener: NWListener?
    private var probeConnection: NWConnection?
    private var probeTimer: Timer?
    private let queue = DispatchQueue(label: "com.toinfinity.clientviewer.discovery")

    /// Fixed local port so HostAgent's unicast reply has somewhere known
    /// to land. Distinct from `ProtocolConstants.udpDiscoveryPort` (that's
    /// the port HostAgent listens on for probes).
    private let localReplyPort: UInt16 = 53213

    /// Hosts not re-announced within this window are dropped from the list.
    private let staleTimeout: TimeInterval = 8.0

    func start() {
        guard listener == nil else { return }
        do {
            try startListener()
            startProbeTimer()
        } catch {
            Log.error("DiscoveryClient failed to start: \(error)")
        }
    }

    func stop() {
        probeTimer?.invalidate()
        probeTimer = nil
        probeConnection?.cancel()
        probeConnection = nil
        listener?.cancel()
        listener = nil
        hosts.removeAll()
    }

    private func startListener() throws {
        guard let port = NWEndpoint.Port(rawValue: localReplyPort) else {
            throw NetworkClientError.invalidPort(localReplyPort)
        }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let newListener = try NWListener(using: params, on: port)
        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleReplyConnection(connection)
        }
        newListener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                Log.error("DiscoveryClient listener failed: \(error)")
            }
        }
        newListener.start(queue: queue)
        self.listener = newListener
    }

    private func startProbeTimer() {
        sendProbe()
        probeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sendProbe()
            Task { @MainActor in self?.pruneStaleHosts() }
        }
    }

    private func sendProbe() {
        guard let discoveryPort = NWEndpoint.Port(rawValue: ProtocolConstants.udpDiscoveryPort),
              let localPort = NWEndpoint.Port(rawValue: localReplyPort),
              let probeData = try? DiscoveryMessageCodec.encode(DiscoveryQuery()) else { return }

        probeConnection?.cancel()

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "0.0.0.0", port: localPort)

        let connection = NWConnection(host: "255.255.255.255", port: discoveryPort, using: params)
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: probeData, completion: .contentProcessed { error in
                    if let error {
                        Log.warn("Discovery probe send failed: \(error)")
                    }
                })
            } else if case .failed(let error) = state {
                Log.warn("Discovery probe connection failed: \(error)")
            }
        }
        connection.start(queue: queue)
        self.probeConnection = connection
    }

    private func handleReplyConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receiveMessage { [weak self] data, _, _, error in
            defer { connection.cancel() }
            guard let self else { return }
            if let error {
                Log.warn("Discovery reply receive error: \(error)")
                return
            }
            guard let data,
                  let decoded = DiscoveryMessageCodec.tryDecode(data),
                  case .announce(let announce) = decoded else { return }

            let remoteAddress: NWEndpoint.Host
            if case let .hostPort(host, _) = connection.currentPath?.remoteEndpoint {
                remoteAddress = host
            } else {
                remoteAddress = "0.0.0.0"
            }

            Task { @MainActor in
                self.upsert(announce: announce, address: remoteAddress)
            }
        }
    }

    @MainActor
    private func upsert(announce: DiscoveryAnnounce, address: NWEndpoint.Host) {
        guard let controlPort = UInt16(exactly: announce.controlPort) else { return }
        let host = DiscoveredHost(
            hostID: announce.deviceId,
            hostName: announce.name,
            platform: announce.os,
            controlPort: controlPort,
            address: address,
            lastSeen: Date()
        )
        if let index = hosts.firstIndex(where: { $0.hostID == host.hostID }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
    }

    @MainActor
    private func pruneStaleHosts() {
        let cutoff = Date().addingTimeInterval(-staleTimeout)
        hosts.removeAll { $0.lastSeen < cutoff }
    }
}

enum NetworkClientError: Error, CustomStringConvertible {
    case invalidPort(UInt16)
    var description: String {
        switch self {
        case .invalidPort(let p): return "Invalid TCP/UDP port: \(p)"
        }
    }
}
