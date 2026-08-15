//
//  VideoDecoder.swift
//  ClientViewer
//
//  Parses the incoming video TCP byte stream into discrete
//  VideoFrameHeader + JPEG payload frames, and decodes each JPEG payload
//  into a CGImage via ImageIO's CGImageSource.
//
import CoreGraphics
import Foundation
import ImageIO
import ToInfinityProtocol

/// Incrementally reassembles `VideoFrameHeader`-prefixed JPEG frames from a
/// raw byte stream (TCP delivers an unstructured byte stream, so frame
/// boundaries must be recovered from the header's declared payload length).
final class VideoFrameStreamParser {
    private var buffer = Data()

    /// Feed newly-received bytes in; returns zero or more complete
    /// (header, jpegPayload) pairs found in the buffer so far.
    func append(_ data: Data) -> [(VideoFrameHeader, Data)] {
        buffer.append(data)
        var results: [(VideoFrameHeader, Data)] = []

        while true {
            guard buffer.count >= VideoFrameHeader.headerSize else { break }

            let headerData = buffer.prefix(VideoFrameHeader.headerSize)
            guard let header = VideoFrameHeader.decode(from: headerData) else {
                // Corrupt/unsynchronized stream — drop one byte and retry
                // to attempt resync rather than stalling forever.
                Log.warn("VideoFrameStreamParser: failed to decode header, dropping 1 byte to resync")
                buffer.removeFirst()
                continue
            }

            let totalFrameSize = VideoFrameHeader.headerSize + Int(header.frameLen)
            guard buffer.count >= totalFrameSize else { break }

            let payload = buffer.subdata(in: VideoFrameHeader.headerSize..<totalFrameSize)
            results.append((header, payload))
            buffer.removeSubrange(0..<totalFrameSize)
        }

        return results
    }

    func reset() {
        buffer.removeAll()
    }
}

enum JPEGDecoder {
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
