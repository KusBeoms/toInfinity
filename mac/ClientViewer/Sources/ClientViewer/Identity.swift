//
//  Identity.swift
//  ClientViewer
//
//  Stable per-machine identifier persisted to disk, mirrors
//  ../../HostAgent/Sources/HostAgent/HostAgentController.swift's
//  HostIdentity so a given Mac announces the same deviceID whether it's
//  acting as Host or Client.
//
import Foundation

enum HostIdentity {
    static func persistentID() -> String {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ToInfinity", isDirectory: true)
            .appendingPathComponent("client-id.txt")

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
