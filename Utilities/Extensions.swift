import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#endif

// MARK: - Collection Extensions

extension Collection {
    /// Safe subscript that returns nil if index is out of bounds.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Sequence Extensions

extension Sequence {
    /// Returns an array with duplicate elements removed, keeping the first occurrence.
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// Formats the time interval as "mm:ss" or "h:mm:ss".
    var formattedDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}


// MARK: - URL Extensions

extension URL {
    
    var miniThumbnailURL: URL? {
        thumbnail(size: 100)
    }
    
    /// Returns a card-sized thumbnail URL (226px).
    var cardThumbnailURL: URL? {
        #if os(iOS)
        thumbnail(size: 320)
        #else
        thumbnail(size: 460)
        #endif
    }

    /// Returns a hero-sized thumbnail URL (900px for large displays).
    var heroThumbnailURL: URL? {
        thumbnail(size: 900)
    }

    /// Returns a thumbnail URL with custom size.
    func thumbnail(size: Int) -> URL? {
        let urlString = absoluteString

        // Handle lh3.googleusercontent.com URLs (format: =w60-h60-l90-rj)
        if urlString.contains("lh3.googleusercontent.com") {
            // Replace existing =wXXX-hXXX with new size, preserving suffix like -l90-rj
            let cleaned = urlString.replacingOccurrences(
                of: #"=w\d+-h\d+"#,
                with: "=w\(size)-h\(size)",
                options: .regularExpression
            )
            return URL(string: cleaned)
        }

        // Handle yt3.ggpht.com and yt3.googleusercontent.com URLs
        if urlString.contains("yt3.ggpht.com") || urlString.contains("yt3.googleusercontent.com") {
            // Remove existing size params and add new ones
            var cleaned = urlString.replacingOccurrences(
                of: #"-w\d+-h\d+"#,
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"-s\d+"#,
                with: "",
                options: .regularExpression
            )
            return URL(string: "\(cleaned)-w\(size)-h\(size)-s\(size)")
        }

        // Handle ytimg.com URLs (standard YouTube thumbnails)
        if urlString.contains("ytimg.com") {
            var result = urlString
            result = result.replacingOccurrences(of: "w60-h60", with: "w\(size)-h\(size)")
            result = result.replacingOccurrences(of: "w120-h120", with: "w\(size)-h\(size)")
            return URL(string: result)
        }

        return self
    }
}

// MARK: - String Extensions

extension String {
    /// Returns a truncated version of the string.
    func truncated(to length: Int, trailing: String = "…") -> String {
        if count > length {
            return String(prefix(length)) + trailing
        }
        return self
    }
}

// MARK: - Color Extensions

extension Color {
    /// Creates a Color from a hex string (e.g., "#FF5733" or "FF5733").
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let length = hexSanitized.count
        switch length {
        case 6: // RGB
            let red = Double((rgb >> 16) & 0xFF) / 255.0
            let green = Double((rgb >> 8) & 0xFF) / 255.0
            let blue = Double(rgb & 0xFF) / 255.0
            self.init(red: red, green: green, blue: blue)
        case 8: // ARGB
            let red = Double((rgb >> 16) & 0xFF) / 255.0
            let green = Double((rgb >> 8) & 0xFF) / 255.0
            let blue = Double(rgb & 0xFF) / 255.0
            let alpha = Double((rgb >> 24) & 0xFF) / 255.0
            self.init(red: red, green: green, blue: blue, opacity: alpha)
        default:
            return nil
        }
    }

    /// Converts the color to a hex string.
    func toHex() -> String? {
        #if os(macOS)
        let cgColor = NSColor(self).cgColor
        guard let components = cgColor.components,
              components.count >= 3 else {
            return nil
        }
        #else
        let cgColor = UIColor(self).cgColor
        guard let components = cgColor.components,
              components.count >= 3 else {
            return nil
        }
        #endif

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - View Extensions

extension View {
    /// Applies `content` to the view when `conditional` is true.
    @ViewBuilder
    func `if`<Content: View>(_ conditional: Bool, content: (Self) -> Content) -> some View {
        if conditional {
            content(self)
        } else {
            self
        }
    }
}

// MARK: - NSImage Extensions

#if os(macOS)
import AppKit

extension NSImage {
    /// Scales the image while preserving aspect ratio to fit within the target size.
    func scalePreservingAspectRatio(targetSize: NSSize, cornerRadius: CGFloat = 0) -> NSImage {
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height

        let scaleFactor = min(widthRatio, heightRatio)

        let scaledImageSize = NSSize(
            width: size.width * scaleFactor,
            height: size.height * scaleFactor
        )

        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()

        // Apply corner radius clipping if specified
        if cornerRadius > 0 {
            let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: targetSize), xRadius: cornerRadius, yRadius: cornerRadius)
            path.addClip()
        }

        // Center the image if it doesn't fill the target size
        let origin = NSPoint(
            x: (targetSize.width - scaledImageSize.width) / 2,
            y: (targetSize.height - scaledImageSize.height) / 2
        )

        self.draw(
            in: NSRect(origin: origin, size: scaledImageSize),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        return newImage
    }
}
#endif
