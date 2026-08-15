//
//  ClientSession.swift
//  ClientViewer
//
//  Top-level app state: owns discovery, the active HostConnection, and the
//  ExtensionWindowController for whichever physical screen the user picks
//  as the extension surface. Exposed to SwiftUI via @EnvironmentObject.
//
import AppKit
import Combine
import Foundation

@MainActor
final class ClientSession: ObservableObject {
    let discovery = DiscoveryClient()
    let connection = HostConnection()

    @Published var selectedHost: DiscoveredHost?
    @Published var pin: String = ""
    @Published var selectedScreen: NSScreen?
    @Published var errorMessage: String?

    private var extensionWindow: ExtensionWindowController?
    private var cancellables = Set<AnyCancellable>()

    var availableScreens: [NSScreen] {
        // Offer every screen except the one the SwiftUI control window is
        // currently on, since extending onto the screen you're actively
        // using the app from would immediately hide the app window.
        NSScreen.screens.filter { $0 != NSScreen.main }.isEmpty
            ? NSScreen.screens
            : NSScreen.screens.filter { $0 != NSScreen.main }
    }

    init() {
        discovery.start()

        connection.$state
            .sink { [weak self] state in
                self?.handleConnectionState(state)
            }
            .store(in: &cancellables)

        connection.onFrame = { [weak self] image in
            self?.extensionWindow?.updateFrame(image)
        }
    }

    func connect(to host: DiscoveredHost) {
        guard let screen = selectedScreen ?? availableScreens.first else {
            errorMessage = "No display available to extend onto."
            return
        }
        selectedHost = host
        errorMessage = nil

        let window = ExtensionWindowController(screen: screen, connection: connection)
        extensionWindow = window

        connection.connect(to: host, pin: pin)
    }

    func disconnect() {
        connection.disconnect()
        extensionWindow?.dismiss()
        extensionWindow = nil
        selectedHost = nil
    }

    private func handleConnectionState(_ state: HostConnectionState) {
        switch state {
        case .paired, .streaming:
            extensionWindow?.setRemoteResolution(width: connection.remoteWidth, height: connection.remoteHeight)
            extensionWindow?.present()
        case .failed(let message):
            errorMessage = message
            extensionWindow?.dismiss()
            extensionWindow = nil
        case .idle:
            extensionWindow?.dismiss()
            extensionWindow = nil
        case .connecting, .awaitingPin:
            break
        }
    }
}
