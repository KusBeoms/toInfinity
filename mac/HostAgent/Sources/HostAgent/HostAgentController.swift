//
//  HostAgentController.swift
//  HostAgent
//
//  Wires together: VirtualDisplayKit (the display) -> ScreenCapture
//  (frames) -> JPEGEncoder -> VideoServer (streams to the connected
//  Client), plus ControlServer (handshake/pairing/input) and
//  DiscoveryResponder (UDP discovery).
//
//  SPEC.md defines no explicit startStream/stopStream control messages:
//  the Host streams once a Client is paired on the control channel AND has
//  opened the separate video TCP connection (SPEC.md §2.1 PairResponse,
//  §3). Capture starts when both conditions hold and stops when either
//  connection drops.
//
import CoreGraphics
import Foundation
import ToInfinityProtocol
import VirtualDisplayKit

final class HostAgentController {
    private let options: HostAgentOptions
    private var virtualDisplay: VirtualDisplay?
    private var screenCapture: ScreenCapture?
    private let videoServer = VideoServer(port: ProtocolConstants.tcpVideoPort)
    private let controlServer: ControlServer
    private let discoveryResponder: DiscoveryResponder
    private let inputInjector = InputInjector()

    init(options: HostAgentOptions) {
        self.options = options
        let hostID = HostIdentity.persistentID()
        self.controlServer = ControlServer(
            port: ProtocolConstants.tcpControlPort,
            expectedPin: options.pin,
            deviceID: hostID,
            deviceName: options.displayName,
            displayWidth: options.width,
            displayHeight: options.height,
            refreshHz: Int(options.refreshRate)
        )
        self.discoveryResponder = DiscoveryResponder(
            hostID: hostID,
            hostName: options.displayName,
            controlPort: ProtocolConstants.tcpControlPort,
            displayWidth: options.width,
            displayHeight: options.height,
            refreshHz: Int(options.refreshRate)
        )
    }

    func start() throws {
        let display = try VirtualDisplay.createChecked(
            width: options.width,
            height: options.height,
            refreshRate: options.refreshRate,
            name: options.displayName
        )
        self.virtualDisplay = display
        Log.info("Created virtual display: \(display)")

        inputInjector.configure(displayID: display.cgDisplayID, displayWidth: options.width, displayHeight: options.height)

        // When the control channel accepts input events from the Client,
        // inject them into the virtual display's coordinate space.
        controlServer.onInputEvent = { [weak self] event in
            self?.inputInjector.inject(event)
        }

        controlServer.onClientDisconnected = { [weak self] in
            self?.stopCapture()
        }
        // Normal ordering is pairing then video-connect (SPEC.md §2.1), but
        // guard the reverse ordering defensively too.
        controlServer.onPaired = { [weak self] in
            self?.maybeStartCapture(displayID: display.cgDisplayID)
        }

        // Streaming begins once a Client has both paired on the control
        // channel and opened the video connection.
        videoServer.onClientConnected = { [weak self] in
            self?.maybeStartCapture(displayID: display.cgDisplayID)
        }
        videoServer.onClientDisconnected = { [weak self] in
            self?.stopCapture()
        }

        try controlServer.start()
        try videoServer.start()
        try discoveryResponder.start()

        Log.info("HostAgent ready: control=\(ProtocolConstants.tcpControlPort) video=\(ProtocolConstants.tcpVideoPort) discovery(UDP)=\(ProtocolConstants.udpDiscoveryPort)")
    }

    private func maybeStartCapture(displayID: CGDirectDisplayID) {
        guard controlServer.paired, videoServer.hasConnectedClient else { return }
        startCapture(displayID: displayID)
    }

    private func startCapture(displayID: CGDirectDisplayID) {
        guard screenCapture == nil else { return }
        Log.info("Starting ScreenCaptureKit capture for display \(displayID)")
        let capture = ScreenCapture(displayID: displayID,
                                     width: options.width,
                                     height: options.height,
                                     frameRate: options.refreshRate)
        capture.onFrame = { [weak self] cgImage, timestamp in
            self?.handleCapturedFrame(cgImage, timestamp: timestamp)
        }
        capture.onError = { error in
            Log.error("ScreenCapture error: \(error)")
        }
        self.screenCapture = capture
        capture.start()
    }

    private func stopCapture() {
        guard let capture = screenCapture else { return }
        Log.info("Stopping ScreenCaptureKit capture")
        capture.stop()
        screenCapture = nil
    }

    private func handleCapturedFrame(_ image: CGImage, timestamp: Double) {
        guard videoServer.hasConnectedClient else { return }
        guard let jpegData = JPEGEncoder.encode(image, quality: 0.6) else {
            Log.warn("JPEG encode failed for captured frame")
            return
        }
        // SPEC.md §3.1 requires milliseconds-since-Unix-epoch; the
        // ScreenCaptureKit sample's presentation timestamp is relative to
        // an arbitrary media clock, not the Unix epoch, so wall-clock time
        // at encode is used instead.
        let timestampMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let header = VideoFrameHeader(
            frameLen: UInt32(jpegData.count),
            timestampMs: timestampMs,
            width: UInt32(image.width),
            height: UInt32(image.height),
            codecId: .jpeg
        )
        videoServer.send(header: header, payload: jpegData)
    }

    func shutdown() {
        stopCapture()
        controlServer.stop()
        videoServer.stop()
        discoveryResponder.stop()
        virtualDisplay?.destroy()
        virtualDisplay = nil
    }
}

/// Stable per-machine identifier persisted to disk so the same Mac always
/// announces the same `hostID` across HostAgent restarts.
enum HostIdentity {
    static func persistentID() -> String {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ToInfinity", isDirectory: true)
            .appendingPathComponent("host-id.txt")

        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        let newID = UUID().uuidString
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
        try? newID.write(to: url, atomically: true, encoding: .utf8)
        return newID
    }
}
