//
//  JPEGEncoder.swift
//  HostAgent
//
//  Encodes captured CGImage frames as JPEG using ImageIO's
//  CGImageDestination, per spec.md's MVP video codec choice (JPEG-over-TCP,
//  H.264 documented as a fast-follow).
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum JPEGEncoder {
    /// - Parameter quality: 0.0 (smallest/lowest quality) ... 1.0 (largest/highest quality).
    static func encode(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}
