//
//  VideoServer.swift
//  HostAgent
//
//  TCP video channel: accepts a single Client connection and streams
//  VideoFrameHeader + raw JPEG bytes for each captured frame.
//
import Foundation
import ToInfinityProtocol
import Network

final class VideoServer {
    private let port: UInt16
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.toinfinity.hostagent.video")

    /// Backpressure guard: avoid queuing more frames than the network can
    /// drain, since JPEG frames can be large and SCStream will keep
    /// producing them regardless of send completion.
    private var sendInFlight = false

    var hasConnectedClient: Bool {
        connection?.state == .ready
    }

    var onClientConnected: (() -> Void)?
    var onClientDisconnected: (() -> Void)?

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NetworkSetupError.invalidPort(port)
        }
        // Video is latency-sensitive; disable Nagle-style coalescing delay
        // (TCP_NODELAY) so small frame headers aren't held back waiting to
        // coalesce with the following JPEG payload.
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.allowLocalEndpointReuse = true

        let newListener = try NWListener(using: params, on: nwPort)
        newListener.newConnectionHandler = { [weak self] connection in
            self?.acceptConnection(connection)
        }
        newListener.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                Log.info("VideoServer listening on TCP \(self?.port ?? 0)")
            } else if case .failed(let error) = state {
                Log.error("VideoServer listener failed: \(error)")
            }
        }
        newListener.start(queue: queue)
        self.listener = newListener
    }

    func stop() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
    }

    private func acceptConnection(_ newConnection: NWConnection) {
        connection?.cancel()
        sendInFlight = false
        newConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Log.info("Video client connected")
                self?.onClientConnected?()
            case .failed(let error):
                Log.warn("Video connection failed: \(error)")
                self?.onClientDisconnected?()
            case .cancelled:
                self?.onClientDisconnected?()
            default:
                break
            }
        }
        newConnection.start(queue: queue)
        self.connection = newConnection
    }

    /// Sends one frame. Drops the frame (rather than queuing unbounded
    /// memory) if a previous send hasn't completed yet — the next captured
    /// frame will supersede it anyway.
    func send(header: VideoFrameHeader, payload: Data) {
        guard let connection, connection.state == .ready else { return }
        guard !sendInFlight else { return }

        var packet = header.encode()
        packet.append(payload)

        sendInFlight = true
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            self?.sendInFlight = false
            if let error {
                Log.warn("Video send failed: \(error)")
            }
        })
    }
}
