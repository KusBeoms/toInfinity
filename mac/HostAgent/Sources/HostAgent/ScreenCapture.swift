//
//  ScreenCapture.swift
//  HostAgent
//
//  Captures frames from the virtual display using ScreenCaptureKit,
//  scoped via an SCContentFilter to the single SCDisplay matching the
//  virtual display's CGDirectDisplayID.
//
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit

final class ScreenCapture: NSObject {
    private let displayID: CGDirectDisplayID
    private let width: Int
    private let height: Int
    private let frameRate: Double

    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "com.toinfinity.hostagent.capture")
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Called on `outputQueue` for every captured frame.
    var onFrame: ((CGImage, Double) -> Void)?
    var onError: ((Error) -> Void)?

    init(displayID: CGDirectDisplayID, width: Int, height: Int, frameRate: Double) {
        self.displayID = displayID
        self.width = width
        self.height = height
        self.frameRate = frameRate
        super.init()
    }

    func start() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false
                )
                guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw ScreenCaptureError.displayNotFound(displayID)
                }

                let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

                let config = SCStreamConfiguration()
                config.width = width
                config.height = height
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(max(frameRate, 1)))
                config.queueDepth = 5
                config.showsCursor = true
                config.scalesToFit = true

                let newStream = SCStream(filter: filter, configuration: config, delegate: self)
                try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
                try await newStream.startCapture()
                self.stream = newStream
                Log.info("ScreenCaptureKit stream started for SCDisplay \(scDisplay.displayID)")
            } catch {
                onError?(error)
            }
        }
    }

    func stop() {
        guard let stream else { return }
        Task {
            try? await stream.stopCapture()
        }
        self.stream = nil
    }
}

enum ScreenCaptureError: Error, CustomStringConvertible {
    case displayNotFound(CGDirectDisplayID)
    case pixelBufferMissing
    case cgImageConversionFailed

    var description: String {
        switch self {
        case .displayNotFound(let id): return "No SCDisplay found matching CGDirectDisplayID \(id)"
        case .pixelBufferMissing: return "CMSampleBuffer had no image pixel buffer"
        case .cgImageConversionFailed: return "Failed to convert captured frame to CGImage"
        }
    }
}

extension ScreenCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }

        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRawValue = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue),
              status == .complete else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            onError?(ScreenCaptureError.pixelBufferMissing)
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            onError?(ScreenCaptureError.cgImageConversionFailed)
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        onFrame?(cgImage, timestamp)
    }
}

extension ScreenCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }
}
