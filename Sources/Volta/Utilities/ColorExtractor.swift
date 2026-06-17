import UIKit
import CoreImage
import SwiftUI

// Tiny color helpers for artwork-driven backgrounds.
enum ColorExtractor {

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

    // dark full-screen variant
    static func backgroundVariant(of color: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // A little saturation, then enough darkness for white UI.
        return UIColor(hue: h, saturation: min(s * 1.15, 1.0), brightness: max(b * 0.52, 0.12), alpha: 1)
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
}
