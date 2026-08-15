//
//  main.swift
//  HostAgent
//
//  Entry point. Creates a virtual display via VirtualDisplayKit, then
//  starts the full Host pipeline: ScreenCaptureKit capture -> JPEG encode
//  -> video TCP stream, plus the control channel (handshake/pairing),
//  UDP discovery responder, and CGEvent input injection.
//
//  Usage (defaults shown):
//    HostAgent [--width 1920] [--height 1080] [--refresh 60] \
//              [--name "toInfinity"] [--pin 000000]
//
import Foundation

struct HostAgentOptions {
    var width: Int = 1920
    var height: Int = 1080
    var refreshRate: Double = 60.0
    var displayName: String = "toInfinity"
    var pin: String = "000000"

    static func parse(_ args: [String]) -> HostAgentOptions {
        var options = HostAgentOptions()
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--width":
                if let v = iterator.next().flatMap(Int.init) { options.width = v }
            case "--height":
                if let v = iterator.next().flatMap(Int.init) { options.height = v }
            case "--refresh":
                if let v = iterator.next().flatMap(Double.init) { options.refreshRate = v }
            case "--name":
                if let v = iterator.next() { options.displayName = v }
            case "--pin":
                if let v = iterator.next() { options.pin = v }
            default:
                break
            }
        }
        return options
    }
}

let options = HostAgentOptions.parse(Array(CommandLine.arguments.dropFirst()))

Log.info("Starting HostAgent: \(options.width)x\(options.height)@\(options.refreshRate)Hz, name='\(options.displayName)'")

let controller = HostAgentController(options: options)

// Handle Ctrl-C / SIGTERM for clean virtual-display teardown.
let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)
signalSource.setEventHandler {
    Log.info("Received SIGINT, shutting down...")
    controller.shutdown()
    exit(0)
}
signalSource.resume()

do {
    try controller.start()
} catch {
    Log.error("Failed to start HostAgent: \(error)")
    exit(1)
}

// Keep the executable alive; all work happens on Network.framework /
// ScreenCaptureKit callback queues.
dispatchMain()
