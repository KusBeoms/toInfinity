//
//  ToInfinityClientApp.swift
//  ClientViewer
//
//  SwiftUI app entry point. Hosts the discovery/connect UI in a normal
//  window; the actual "extended desktop" surface is a separate borderless
//  NSWindow created by ExtensionWindowController once connected (see
//  ExtensionWindowController.swift), not this SwiftUI window itself.
//
import AppKit
import SwiftUI

@main
struct ToInfinityClientApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = ClientSession()

    var body: some Scene {
        WindowGroup("toInfinity") {
            ContentView()
                .environmentObject(session)
                .frame(minWidth: 420, minHeight: 480)
        }
        .windowResizability(.contentSize)
    }
}

/// Minimal AppDelegate: ensures the app behaves as a regular foreground
/// app (Dock icon, menu bar) since this is a user-facing utility, not a
/// background agent.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
