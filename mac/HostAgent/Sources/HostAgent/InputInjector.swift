//
//  InputInjector.swift
//  HostAgent
//
//  Translates incoming binary InputEvents (SPEC.md §4: normalized 0-65535
//  virtual-display coordinate space, USB HID usage IDs for keys) into
//  CGEvents posted into the HID event stream, offset into the virtual
//  display's actual position in global display coordinate space.
//
import CoreGraphics
import Foundation
import ToInfinityProtocol

final class InputInjector {
    private var displayID: CGDirectDisplayID?
    private var eventSource: CGEventSource?
    private var displayWidth: Int = 0
    private var displayHeight: Int = 0

    func configure(displayID: CGDirectDisplayID, displayWidth: Int, displayHeight: Int) {
        self.displayID = displayID
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.eventSource = CGEventSource(stateID: .hidSystemState)
    }

    func inject(_ event: InputEvent) {
        guard let displayID else { return }
        let origin = CGDisplayBounds(displayID).origin

        switch event {
        case .mouseMove(let x, let y):
            post(mouseType: .mouseMoved, at: globalPoint(x, y, origin: origin), button: .left)

        case .mouseButtonDown(let x, let y, let button):
            let (type, cgButton) = mouseDownEvent(for: button)
            post(mouseType: type, at: globalPoint(x, y, origin: origin), button: cgButton)

        case .mouseButtonUp(let x, let y, let button):
            let (type, cgButton) = mouseUpEvent(for: button)
            post(mouseType: type, at: globalPoint(x, y, origin: origin), button: cgButton)

        case .mouseWheel(let x, let y, let deltaX, let deltaY):
            injectScroll(deltaX: deltaX, deltaY: deltaY, at: globalPoint(x, y, origin: origin))

        case .keyDown(let hidUsage):
            injectKey(hidUsage: hidUsage, keyDown: true)

        case .keyUp(let hidUsage):
            injectKey(hidUsage: hidUsage, keyDown: false)
        }
    }

    /// Converts SPEC.md §4.1 normalized 0-65535 coordinates into this
    /// display's pixel space, then offsets into global display coordinates.
    private func globalPoint(_ x: UInt16, _ y: UInt16, origin: CGPoint) -> CGPoint {
        let pixelX = (Double(x) / 65535.0) * Double(displayWidth)
        let pixelY = (Double(y) / 65535.0) * Double(displayHeight)
        return CGPoint(x: origin.x + pixelX, y: origin.y + pixelY)
    }

    private func mouseDownEvent(for button: MouseButton) -> (CGEventType, CGMouseButton) {
        switch button {
        case .right: return (.rightMouseDown, .right)
        case .middle, .x1, .x2: return (.otherMouseDown, .center)
        default: return (.leftMouseDown, .left)
        }
    }

    private func mouseUpEvent(for button: MouseButton) -> (CGEventType, CGMouseButton) {
        switch button {
        case .right: return (.rightMouseUp, .right)
        case .middle, .x1, .x2: return (.otherMouseUp, .center)
        default: return (.leftMouseUp, .left)
        }
    }

    private func post(mouseType: CGEventType, at point: CGPoint, button: CGMouseButton) {
        guard let event = CGEvent(mouseEventSource: eventSource, mouseType: mouseType,
                                   mouseCursorPosition: point, mouseButton: button) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    private func injectScroll(deltaX: Int16, deltaY: Int16, at point: CGPoint) {
        // Move the cursor to the target point first so the scroll applies
        // to the right window/control, then post the scroll wheel event.
        if let moveEvent = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved,
                                    mouseCursorPosition: point, mouseButton: .left) {
            moveEvent.post(tap: .cghidEventTap)
        }
        guard let scrollEvent = CGEvent(scrollWheelEvent2Source: eventSource,
                                         units: .pixel,
                                         wheelCount: 2,
                                         wheel1: Int32(deltaY),
                                         wheel2: Int32(deltaX),
                                         wheel3: 0) else {
            return
        }
        scrollEvent.post(tap: .cghidEventTap)
    }

    private func injectKey(hidUsage: UInt16, keyDown: Bool) {
        guard let cgKeyCode = HIDKeyCodeMap.hidUsageToCGKeyCode[hidUsage] else {
            Log.warn("InputInjector: no CGKeyCode mapping for HID usage 0x\(String(hidUsage, radix: 16))")
            return
        }
        guard let event = CGEvent(keyboardEventSource: eventSource,
                                   virtualKey: cgKeyCode,
                                   keyDown: keyDown) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
