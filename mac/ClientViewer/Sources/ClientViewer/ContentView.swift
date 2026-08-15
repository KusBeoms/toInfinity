//
//  ContentView.swift
//  ClientViewer
//
//  Discovery list + connect UI. The actual extended-desktop rendering
//  happens in a separate borderless NSWindow (ExtensionWindowController),
//  not in this SwiftUI view.
//
import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: ClientSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if session.selectedHost != nil {
                connectedView
            } else {
                discoveryList
                connectForm
            }
        }
        .padding(20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("toInfinity")
                .font(.title2)
                .bold()
            Text("Extend this Mac onto a display offered by another machine on your network.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var discoveryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available Hosts")
                .font(.headline)

            if session.discovery.hosts.isEmpty {
                Text("Searching for hosts on your local network…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                List(session.discovery.hosts) { host in
                    HostRow(host: host, isSelected: session.selectedHost?.id == host.id) {
                        session.selectedHost = host
                    }
                }
                .frame(minHeight: 160, maxHeight: 220)
                .listStyle(.bordered)
            }
        }
    }

    private var connectForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !session.availableScreens.isEmpty {
                Picker("Extend onto", selection: Binding(
                    get: { session.selectedScreen ?? session.availableScreens.first },
                    set: { session.selectedScreen = $0 }
                )) {
                    ForEach(Array(session.availableScreens.enumerated()), id: \.offset) { index, screen in
                        Text(screen.localizedName).tag(screen as NSScreen?)
                    }
                }
            }

            SecureField("PIN", text: $session.pin)
                .textFieldStyle(.roundedBorder)

            Button("Connect") {
                connectToFirstListedHost()
            }
            .disabled(session.discovery.hosts.isEmpty || session.pin.isEmpty)
            .buttonStyle(.borderedProminent)
        }
    }

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let host = session.selectedHost {
                Label("Connected to \(host.hostName)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Button("Disconnect", role: .destructive) {
                session.disconnect()
            }
        }
    }

    private func connectToFirstListedHost() {
        // "Connect" acts on whichever host is highlighted in the list, or
        // the first discovered host if none was explicitly tapped.
        guard let host = session.selectedHost ?? session.discovery.hosts.first else { return }
        session.connect(to: host)
    }
}

private struct HostRow: View {
    let host: DiscoveredHost
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading) {
                    Text(host.hostName).font(.body)
                    Text(host.displaySubtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
