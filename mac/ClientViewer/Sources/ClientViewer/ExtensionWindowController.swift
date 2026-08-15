//
//  ExtensionWindowController.swift
//  ClientViewer
//
//  Renders the incoming frame stream full-screen in a borderless NSWindow
//  positioned on whichever physical NSScreen the user designates as the
//  "extension surface", and captures local mouse/keyboard while that
//  window is key, forwarding it over the input channel via InputForwarder.
//
import AppKit
import CoreGraphics
import ToInfinityProtocol

final class ExtensionWindowController: NSWindowController {
    private let imageView: FrameImageView
    private let inputForwarder: InputForwarder
    private weak var connection: HostConnection?

    init(screen: NSScreen, connection: HostConnection) {
        self.connection = connection
        let contentView = FrameImageView(frame: screen.frame)
        self.imageView = contentView

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = contentView

        self.inputForwarder = InputForwarder(view: contentView, connection: connection)

        super.init(window: window)

        contentView.postsBoundsChangedNotifications = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(imageView)
        inputForwarder.startMonitoring()
    }

    func dismiss() {
        inputForwarder.stopMonitoring()
        window?.orderOut(nil)
    }

    func updateFrame(_ image: CGImage) {
        imageView.updateFrame(image)
    }

    /// No-op: SPEC.md §4.1 input coordinates are normalized 0-65535
    /// independent of the remote virtual display's pixel resolution, so
    /// InputForwarder no longer needs the remote width/height to scale
    /// local coordinates. Kept as a call site for ClientSession.
    func setRemoteResolution(width: Int, height: Int) {}
}

/// Simple layer-backed NSView that draws the latest decoded CGImage,
/// scaled to fill its bounds (matching `SCStreamConfiguration.scalesToFit`
/// on the Host side, so remote/local aspect ratios are expected to match).
final class FrameImageView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateFrame(_ image: CGImage) {
        layer?.contents = image
    }
}
