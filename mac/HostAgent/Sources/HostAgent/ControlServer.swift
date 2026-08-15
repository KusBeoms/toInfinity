//
//  ControlServer.swift
//  HostAgent
//
//  TCP control channel (SPEC.md §2, amended by §4): accepts a single Client
//  connection, sends our Hello immediately without waiting (per SPEC.md
//  "the acceptor replies with its own Hello without waiting"), handles the
//  PairRequest/PairResponse handshake, and demultiplexes framed input
//  events (frameKind 0x02) from JSON control messages (frameKind 0x01) on
//  the same connection.
//
import Foundation
import ToInfinityProtocol
import Network

final class ControlServer {
    private let port: UInt16
    private let expectedPin: String
    private let deviceID: String
    private let deviceName: String
    private let displayWidth: Int
    private let displayHeight: Int
    private let refreshHz: Int

    private var listener: NWListener?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private let queue = DispatchQueue(label: "com.toinfinity.hostagent.control")

    private(set) var paired = false

    var onInputEvent: ((InputEvent) -> Void)?
    var onPaired: (() -> Void)?
    var onClientDisconnected: (() -> Void)?

    init(port: UInt16, expectedPin: String, deviceID: String, deviceName: String,
         displayWidth: Int, displayHeight: Int, refreshHz: Int) {
        self.port = port
        self.expectedPin = expectedPin
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.refreshHz = refreshHz
    }

    func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NetworkSetupError.invalidPort(port)
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let newListener = try NWListener(using: params, on: nwPort)
        newListener.newConnectionHandler = { [weak self] connection in
            self?.acceptConnection(connection)
        }
        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                Log.error("ControlServer listener failed: \(error)")
            case .ready:
                Log.info("ControlServer listening on TCP \(self?.port ?? 0)")
            default:
                break
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
        // MVP supports a single connected Client at a time (spec.md
        // non-goals: multi-client). Replace any existing connection.
        connection?.cancel()
        receiveBuffer.removeAll()
        paired = false

        newConnection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.info("Control client connected")
                // SPEC.md §2.1 Hello: "the acceptor replies with its own
                // Hello without waiting" — send ours immediately.
                self.send(self.makeHello(), on: newConnection)
            case .failed(let error):
                Log.warn("Control connection failed: \(error)")
                self.handleDisconnect()
            case .cancelled:
                self.handleDisconnect()
            default:
                break
            }
        }
        newConnection.start(queue: queue)
        self.connection = newConnection
        receiveNext(on: newConnection)
    }

    private func handleDisconnect() {
        paired = false
        onClientDisconnected?()
    }

    private func makeHello() -> Hello {
        Hello(
            deviceId: deviceID,
            name: deviceName,
            os: "macos",
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            refreshHz: refreshHz,
            codecs: ["jpeg"]
        )
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer(on: connection)
            }
            if let error {
                Log.warn("Control receive error: \(error)")
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            self.receiveNext(on: connection)
        }
    }

    /// SPEC.md §4 framing: `[len:4 big-endian][kind:1][payload:len-1]`.
    /// Drains as many complete frames as are currently buffered.
    private func processBuffer(on connection: NWConnection) {
        while true {
            guard receiveBuffer.count >= ControlFrame.lengthPrefixSize else { return }

            let bodyLength: Int
            do {
                bodyLength = try ControlFrame.readLengthPrefix(receiveBuffer.prefix(ControlFrame.lengthPrefixSize))
            } catch {
                Log.warn("Control frame length prefix invalid, closing connection: \(error)")
                connection.cancel()
                receiveBuffer.removeAll()
                return
            }

            let totalFrameSize = ControlFrame.lengthPrefixSize + bodyLength
            guard receiveBuffer.count >= totalFrameSize else { return }

            let body = receiveBuffer.subdata(in: ControlFrame.lengthPrefixSize..<totalFrameSize)
            receiveBuffer.removeSubrange(0..<totalFrameSize)

            guard let frame = try? ControlFrame.decodeBody(body) else {
                Log.warn("Control frame body malformed, dropping")
                continue
            }
            handle(frame, on: connection)
        }
    }

    private func handle(_ frame: ControlFrame.DecodedFrame, on connection: NWConnection) {
        switch frame.kind {
        case .json:
            guard let decoded = ControlMessageCodec.tryDecode(frame.payload) else { return }
            handleControlMessage(decoded, on: connection)
        case .inputEvent:
            guard paired, let event = InputEvent.decode(from: frame.payload) else { return }
            onInputEvent?(event)
        default:
            break
        }
    }

    private func handleControlMessage(_ message: DecodedControlMessage, on connection: NWConnection) {
        switch message {
        case .hello(let hello):
            Log.info("Hello from \(hello.name) [\(hello.deviceId)] (\(hello.os))")

        case .pairRequest(let request):
            let accepted = request.pin == expectedPin
            paired = accepted
            Log.info(accepted ? "Pairing accepted" : "Pairing rejected (bad PIN)")
            send(PairResponse(accepted: accepted, reason: accepted ? nil : "wrong_pin"), on: connection)
            if accepted {
                onPaired?()
            }

        case .pairResponse:
            // Not expected from a Client in this direction; ignore.
            break

        case .bye(let bye):
            Log.info("Client said bye: \(bye.reason)")
            connection.cancel()
        }
    }

    private func send(_ message: ControlMessage, on connection: NWConnection) {
        guard let data = try? ControlFrame.encodeJson(message) else {
            Log.warn("Failed to encode control message")
            return
        }
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                Log.warn("Control send failed: \(error)")
            }
        })
    }
}

enum NetworkSetupError: Error, CustomStringConvertible {
    case invalidPort(UInt16)
    var description: String {
        switch self {
        case .invalidPort(let p): return "Invalid TCP/UDP port: \(p)"
        }
    }
}
