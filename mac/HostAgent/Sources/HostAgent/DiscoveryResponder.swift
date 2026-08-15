//
//  DiscoveryResponder.swift
//  HostAgent
//
//  Responds to UDP discovery datagrams per SPEC.md §1.2: listens on
//  ProtocolConstants.udpDiscoveryPort for "query" datagrams and replies
//  unicast to the sender with an "announce" datagram describing this Host
//  (deviceId, name, os, controlPort, and the virtual display's current
//  width/height/refreshHz).
//
import Foundation
import ToInfinityProtocol
import Network

final class DiscoveryResponder {
    private let hostID: String
    private let hostName: String
    private let controlPort: UInt16
    private let displayWidth: Int
    private let displayHeight: Int
    private let refreshHz: Int

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.toinfinity.hostagent.discovery")

    init(hostID: String, hostName: String, controlPort: UInt16, displayWidth: Int, displayHeight: Int, refreshHz: Int) {
        self.hostID = hostID
        self.hostName = hostName
        self.controlPort = controlPort
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.refreshHz = refreshHz
    }

    func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: ProtocolConstants.udpDiscoveryPort) else {
            throw NetworkSetupError.invalidPort(ProtocolConstants.udpDiscoveryPort)
        }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.allowFastOpen = true

        let newListener = try NWListener(using: params, on: nwPort)
        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleProbe(connection)
        }
        newListener.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                Log.info("DiscoveryResponder listening on UDP \(ProtocolConstants.udpDiscoveryPort)")
            } else if case .failed(let error) = state {
                Log.error("DiscoveryResponder listener failed: \(error)")
            }
        }
        newListener.start(queue: queue)
        self.listener = newListener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleProbe(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            defer { connection.cancel() }

            if let error {
                Log.warn("Discovery probe receive error: \(error)")
                return
            }
            guard let data else { return }

            // Only "query" datagrams (SPEC.md §1.2) elicit a reply.
            // Unknown/"announce" datagrams are ignored per SPEC.md §6.
            guard let decoded = DiscoveryMessageCodec.tryDecode(data), case .query = decoded else { return }

            let announce = DiscoveryAnnounce(
                deviceId: self.hostID,
                name: self.hostName,
                os: "macos",
                controlPort: Int(self.controlPort),
                displayWidth: self.displayWidth,
                displayHeight: self.displayHeight,
                refreshHz: self.refreshHz
            )
            guard let responseData = try? DiscoveryMessageCodec.encode(announce) else { return }
            connection.send(content: responseData, completion: .contentProcessed { error in
                if let error {
                    Log.warn("Discovery response send failed: \(error)")
                }
            })
        }
    }
}
