//
//  InputForwarder.swift
//  ClientViewer
//
//  Captures local mouse/keyboard events while the extension window is key
//  and forwards them as binary InputEvents (SPEC.md §4) over
//  HostConnection's control channel. Mouse coordinates are normalized to
//  0-65535 per axis (SPEC.md §4.1) using the local window's bounds — the
//  wire format is resolution-independent, so no remote-resolution scaling
//  is needed here.
//
import AppKit
import CoreGraphics
import ToInfinityProtocol

@MainActor
final class InputForwarder {
    private weak var view: NSView?
    private weak var connection: HostConnection?
    private var localMonitor: Any?

    init(view: NSView, connection: HostConnection) {
        self.view = view
        self.connection = connection
    }

    func startMonitoring() {
        guard localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel, .keyDown, .keyUp
        ]
        localMonitor = NSEvent.addLocalMonitorHandler(matching: mask) { [weak self] event in
            self?.handle(event)
            // Returning the event lets it also be processed locally
            // (e.g. Cmd-Q still works); the window itself has no
            // meaningful local UI to interact with otherwise.
            return event
        }
    }

    func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard let view else { return }

        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let (x, y) = normalizedPoint(for: event, in: view)
            connection?.sendInput(.mouseMove(x: x, y: y))

        case .leftMouseDown:
            let (x, y) = normalizedPoint(for: event, in: view)
            connection?.sendInput(.mouseButtonDown(x: x, y: y, button: .left))
        case .leftMouseUp:
            let (x, y) = normalizedPoint(for: event, in: view)
            connection?.sendInput(.mouseButtonUp(x: x, y: y, button: .left))
        case .rightMouseDown:
            let (x, y) = normalizedPoint(for: event, in: view)
            connection?.sendInput(.mouseButtonDown(x: x, y: y, button: .right))
        case .rightMouseUp:
            let (x, y) = normalizedPoint(for: event, in: view)
            connection?.sendInput(.mouseButtonUp(x: x, y: y, button: .right))
        case .otherMouseDown:
            let (x, y) = normalizedPoint(for: event, in: view)
            connection?.sendInput(.mouseButtonDown(x: x, y: y, button: .middle))
        case .otherMouseUp:
            let (x, y) = normalizedPoint(for: event, in: view)
            connection?.sendInput(.mouseButtonUp(x: x, y: y, button: .middle))

        case .scrollWheel:
            let (x, y) = normalizedPoint(for: event, in: view)
            let deltaX = clampToInt16(event.scrollingDeltaX)
            let deltaY = clampToInt16(event.scrollingDeltaY)
            connection?.sendInput(.mouseWheel(x: x, y: y, deltaX: deltaX, deltaY: deltaY))

        case .keyDown:
            guard let hidUsage = HIDKeyCodeMap.cgKeyCodeToHIDUsage[event.keyCode] else { return }
            connection?.sendInput(.keyDown(hidUsage: hidUsage))
        case .keyUp:
            guard let hidUsage = HIDKeyCodeMap.cgKeyCodeToHIDUsage[event.keyCode] else { return }
            connection?.sendInput(.keyUp(hidUsage: hidUsage))

        default:
            break
        }
    }

    /// Converts a local event's window-space location into SPEC.md §4.1
    /// normalized 0-65535 virtual-display coordinates.
    private func normalizedPoint(for event: NSEvent, in view: NSView) -> (x: UInt16, y: UInt16) {
        let locationInView = view.convert(event.locationInWindow, from: nil)
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return (0, 0) }

        // FrameImageView is flipped (origin top-left) to match remote
        // pixel coordinate conventions, so no Y-flip is needed here.
        let normalizedX = (locationInView.x / bounds.width).clamped(to: 0...1)
        let normalizedY = (locationInView.y / bounds.height).clamped(to: 0...1)

        let x = UInt16((normalizedX * 65535.0).rounded())
        let y = UInt16((normalizedY * 65535.0).rounded())
        return (x, y)
    }

    private func clampToInt16(_ value: CGFloat) -> Int16 {
        let scaled = value * 10 // sub-pixel scroll deltas are fractional; scale for resolution
        let bounded = scaled.clamped(to: CGFloat(Int16.min)...CGFloat(Int16.max))
        return Int16(bounded)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
