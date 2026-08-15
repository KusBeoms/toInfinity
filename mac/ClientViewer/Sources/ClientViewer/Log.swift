//
//  Log.swift
//  ClientViewer
//
//  Minimal stderr logger, mirrors HostAgent/Sources/HostAgent/Log.swift.
//
import Foundation

enum Log {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static func write(_ level: String, _ message: String) {
        let ts = formatter.string(from: Date())
        FileHandle.standardError.write("\(ts) [\(level)] \(message)\n".data(using: .utf8)!)
    }

    static func info(_ message: String) { write("INFO", message) }
    static func warn(_ message: String) { write("WARN", message) }
    static func error(_ message: String) { write("ERROR", message) }
    static func debug(_ message: String) { write("DEBUG", message) }
}
