import UIKit
import CoreImage
import SwiftUI

// Tiny color helpers for artwork-driven backgrounds.
enum ColorExtractor {
    private struct ColorBucket {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var weight: CGFloat = 0

        mutating func add(red: CGFloat, green: CGFloat, blue: CGFloat, weight: CGFloat) {
            self.red += red * weight
            self.green += green * weight
            self.blue += blue * weight
            self.weight += weight
        }

        var color: UIColor {
            guard weight > 0 else { return .black }
            return UIColor(red: red / weight, green: green / weight, blue: blue / weight, alpha: 1)
        }
    }

    static func dominantColor(from image: UIImage) -> UIColor {
        guard let cgImage = image.cgImage else { return .black }
        let ci = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent),
        ]), let output = filter.outputImage else { return .black }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }

    static func dominantColors(from image: UIImage, maxColors: Int = 3) -> [UIColor] {
        guard maxColors > 0 else { return [] }
        guard let cgImage = image.cgImage else { return [dominantColor(from: image)] }

        let width = 24
        let height = 24
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard didDraw else { return [dominantColor(from: image)] }

        var buckets: [Int: ColorBucket] = [:]
        let hueBuckets = 24
        let saturationBuckets = 4
        let brightnessBuckets = 4

        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let alpha = CGFloat(pixels[offset + 3]) / 255
            guard alpha > 0.08 else { continue }

            let red = CGFloat(pixels[offset]) / 255
            let green = CGFloat(pixels[offset + 1]) / 255
            let blue = CGFloat(pixels[offset + 2]) / 255
            let color = UIColor(red: red, green: green, blue: blue, alpha: 1)
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var extractedAlpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &extractedAlpha)

            guard brightness > 0.03 else { continue }

            let hueBin = min(Int(hue * CGFloat(hueBuckets)), hueBuckets - 1)
            let saturationBin = min(Int(saturation * CGFloat(saturationBuckets)), saturationBuckets - 1)
            let brightnessBin = min(Int(brightness * CGFloat(brightnessBuckets)), brightnessBuckets - 1)
            let key = (hueBin << 8) | (saturationBin << 4) | brightnessBin
            let colorWeight = alpha
                * (0.45 + min(saturation, 1) * 0.55)
                * (0.60 + min(brightness, 1) * 0.40)

            var bucket = buckets[key] ?? ColorBucket()
            bucket.add(red: red, green: green, blue: blue, weight: colorWeight)
            buckets[key] = bucket
        }

        var palette: [UIColor] = []
        for candidate in buckets.values.sorted(by: { $0.weight > $1.weight }).map(\.color) {
            guard palette.allSatisfy({ colorDistance(candidate, $0) > 0.18 }) else { continue }
            palette.append(candidate)
            if palette.count == maxColors { break }
        }

        return palette.isEmpty ? [dominantColor(from: image)] : palette
    }

    // dark full-screen variant
    static func backgroundVariant(of color: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // A little saturation, then enough darkness for white UI.
        return UIColor(hue: h, saturation: min(s * 1.15, 1.0), brightness: max(b * 0.52, 0.12), alpha: 1)
    }

    private static func gradientCompanionVariant(of color: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let shiftedHue = h + 0.045 > 1 ? h - 0.955 : h + 0.045
        return UIColor(
            hue: shiftedHue,
            saturation: min(max(s * 1.12, 0.18), 1),
            brightness: max(b * 0.68, 0.08),
            alpha: 1
        )
    }

    private static func colorDistance(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let left = rgbComponents(of: lhs)
        let right = rgbComponents(of: rhs)
        let redDelta = left.red - right.red
        let greenDelta = left.green - right.green
        let blueDelta = left.blue - right.blue
        return sqrt(redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta)
    }

    private static func rgbComponents(of color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return (0, 0, 0)
        }
        return (red, green, blue)
    }

    // true when dark text will read better
    static func isLight(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &bl, alpha: &a)
        // WCAG relative luminance
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * bl
        return luminance > 0.5
    }

    static func backgroundSwiftUI(from image: UIImage) -> Color {
        Color(backgroundVariant(of: dominantColor(from: image)))
    }

    static func backgroundPaletteSwiftUI(from image: UIImage, maxColors: Int = 3) -> [Color] {
        let colors = dominantColors(from: image, maxColors: maxColors).map(backgroundVariant)
        guard let first = colors.first else { return [backgroundSwiftUI(from: image)] }
        if colors.count == 1 {
            return [Color(first), Color(gradientCompanionVariant(of: first))]
        }
        return colors.map(Color.init)
    }
}
