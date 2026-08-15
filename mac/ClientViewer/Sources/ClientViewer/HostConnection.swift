//
//  HostConnection.swift
//  ClientViewer
//
//  Owns both TCP connections to a Host: the control channel (Hello /
//  PairRequest / PairResponse handshake plus input-event forwarding, per
//  SPEC.md §2 and §4) and the video channel (decoded frames delivered via
//  `onFrame`, per SPEC.md §3). SPEC.md defines no startStream/stopStream
//  control messages: the Host begins streaming once pairing succeeds and
//  this side opens the video connection (SPEC.md §2.1, §3).
//
import CoreGraphics
import Foundation
import ToInfinityProtocol
import Network

enum HostConnectionState: Equatable {
    case idle
    case connecting
    case awaitingPin
    case paired
    case streaming
    case failed(String)
}

@MainActor
final class HostConnection: ObservableObject {
    @Published private(set) var state: HostConnectionState = .idle
    @Published private(set) var remoteWidth: Int = 1920
    @Published private(set) var remoteHeight: Int = 1080

    /// Called (on main actor) with each decoded frame.
    var onFrame: ((CGImage) -> Void)?

    private let localDeviceID = HostIdentity.persistentID()
    private var controlConnection: NWConnection?
    private var videoConnection: NWConnection?
    private var controlReceiveBuffer = Data()
    private let videoParser = VideoFrameStreamParser()
    private let queue = DispatchQueue(label: "com.toinfinity.clientviewer.host")

    private var host: DiscoveredHost?
    private var pin: String = ""

    func connect(to host: DiscoveredHost, pin: String) {
        self.host = host
        self.pin = pin
        state = .connecting
        openControlConnection(host: host)
    }

    func disconnect() {
        if let controlConnection, controlConnection.state == .ready {
            sendControl(Bye(reason: "user_disconnected"))
        }
        controlConnection?.cancel()
        controlConnection = nil
        videoConnection?.cancel()
        videoConnection = nil
        controlReceiveBuffer.removeAll()
        videoParser.reset()
        state = .idle
    }

    // MARK: Control channel

    private func openControlConnection(host: DiscoveredHost) {
        guard let port = NWEndpoint.Port(rawValue: host.controlPort) else {
            state = .failed("Invalid control port \(host.controlPort)")
            return
        }
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let connection = NWConnection(host: host.address, port: port, using: params)
        connection.stateUpdateHandler = { [weak self] connectionState in
            Task { @MainActor in
                self?.handleControlState(connectionState)
            }
        }
        connection.start(queue: queue)
        self.controlConnection = connection
    }

    private func handleControlState(_ connectionState: NWConnection.State) {
        switch connectionState {
        case .ready:
            // SPEC.md §2.1: whichever side connects first sends Hello first.
            sendControl(makeHello())
            receiveControlNext()
        case .failed(let error):
            state = .failed("Control connection failed: \(error)")
        case .cancelled:
            if state != .idle { state = .failed("Control connection closed") }
        default:
            break
        }
    }

    private func makeHello() -> Hello {
        Hello(
            deviceId: localDeviceID,
            name: DiscoveredHost.localMachineName(),
            os: "macos",
            displayWidth: 0,
            displayHeight: 0,
            refreshHz: 0,
            codecs: ["jpeg"]
        )
    }

    private func receiveControlNext() {
        guard let controlConnection else { return }
        controlConnection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor in
                if let data, !data.isEmpty {
                    self.controlReceiveBuffer.append(data)
                    self.processControlBuffer()
                }
                if let error {
                    self.state = .failed("Control receive error: \(error)")
                    return
                }
                if isComplete {
                    self.state = .failed("Host closed control connection")
                    return
                }
                self.receiveControlNext()
            }
        }
    }

    /// SPEC.md §4 framing: `[len:4 big-endian][kind:1][payload:len-1]`.
    private func processControlBuffer() {
        while true {
            guard controlReceiveBuffer.count >= ControlFrame.lengthPrefixSize else { return }

            let bodyLength: Int
            do {
                bodyLength = try ControlFrame.readLengthPrefix(controlReceiveBuffer.prefix(ControlFrame.lengthPrefixSize))
            } catch {
                state = .failed("Control frame length prefix invalid: \(error)")
                controlReceiveBuffer.removeAll()
                return
            }

            let totalFrameSize = ControlFrame.lengthPrefixSize + bodyLength
            guard controlReceiveBuffer.count >= totalFrameSize else { return }

            let body = controlReceiveBuffer.subdata(in: ControlFrame.lengthPrefixSize..<totalFrameSize)
            controlReceiveBuffer.removeSubrange(0..<totalFrameSize)

            guard let frame = try? ControlFrame.decodeBody(body) else {
                Log.warn("Control frame body malformed, dropping")
                continue
            }
            // Only JSON control messages are expected inbound on this
            // channel; the Host never sends us binary input events.
            if frame.kind == .json, let decoded = ControlMessageCodec.tryDecode(frame.payload) {
                handle(decoded)
            }
        }
    }

    private func handle(_ message: DecodedControlMessage) {
        switch message {
        case .hello:
            // Host echoed hello; now request pairing.
            state = .awaitingPin
            sendControl(PairRequest(pin: pin))

        case .pairResponse(let response):
            if response.accepted {
                state = .paired
                openVideoConnection()
            } else {
                state = .failed("Pairing rejected: \(response.reason ?? "unknown reason")")
            }

        case .bye(let bye):
            state = .failed("Host said bye: \(bye.reason)")

        case .pairRequest:
            // Not expected from a Host in this direction; ignore.
            break
        }
    }

    private func sendControl(_ message: ControlMessage) {
        guard let controlConnection, let data = try? ControlFrame.encodeJson(message) else { return }
        controlConnection.send(content: data, completion: .contentProcessed { error in
            if let error {
                Log.warn("Control send failed: \(error)")
            }
        })
    }

    /// Forwards a local input event to the Host over the control channel.
    func sendInput(_ event: InputEvent) {
        guard state == .streaming || state == .paired else { return }
        guard let controlConnection else { return }
        let data = ControlFrame.encodeInputEvent(event)
        controlConnection.send(content: data, completion: .contentProcessed { error in
            if let error {
                Log.warn("Input send failed: \(error)")
            }
        })
    }

    // MARK: Video channel

    private func openVideoConnection() {
        guard let host else { return }
        guard let port = NWEndpoint.Port(rawValue: ProtocolConstants.tcpVideoPort) else { return }
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let connection = NWConnection(host: host.address, port: port, using: params)
        connection.stateUpdateHandler = { [weak self] connectionState in
            switch connectionState {
            case .ready:
                Log.info("Video connection ready")
                Task { @MainActor in
                    self?.state = .streaming
                    self?.receiveVideoNext()
                }
            case .failed(let error):
                Log.error("Video connection failed: \(error)")
            default:
                break
            }
        }
        connection.start(queue: queue)
        self.videoConnection = connection
    }

    private func receiveVideoNext() {
        guard let videoConnection else { return }
        videoConnection.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor in
                if let data, !data.isEmpty {
                    let frames = self.videoParser.append(data)
                    for (header, payload) in frames {
                        if let image = JPEGDecoder.decode(payload) {
                            self.remoteWidth = Int(header.width)
                            self.remoteHeight = Int(header.height)
                            self.onFrame?(image)
                        }
                    }
                }
                if let error {
                    Log.error("Video receive error: \(error)")
                    return
                }
                if isComplete { return }
                self.receiveVideoNext()
            }
        }
    }
}

extension DiscoveredHost {
    static func localMachineName() -> String {
        DiscoveredHost.hostNameCache
    }
    private static let hostNameCache: String = {
        #if os(macOS)
        return Foundation.Host.current().localizedName ?? "Mac"
        #else
        return "Mac"
        #endif
    }()
}
