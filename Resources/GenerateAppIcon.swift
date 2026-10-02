import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: GenerateAppIcon.swift <iconset-directory>")
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

let colorSpace = CGColorSpaceCreateDeviceRGB()

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

func drawIcon(in context: CGContext) {
    let background = CGPath(roundedRect: CGRect(x: 38, y: 38, width: 948, height: 948), cornerWidth: 218, cornerHeight: 218, transform: nil)

    context.addPath(background)
    context.clip()
    let backgroundColors = [color(0.075, 0.12, 0.15), color(0.12, 0.22, 0.24)] as CFArray
    let backgroundGradient = CGGradient(colorsSpace: colorSpace, colors: backgroundColors, locations: [0, 1])!
    context.drawLinearGradient(backgroundGradient, start: CGPoint(x: 150, y: 900), end: CGPoint(x: 850, y: 100), options: [])

    context.setStrokeColor(color(0.78, 0.91, 0.87, 0.16))
    context.setLineWidth(24)
    context.strokeEllipse(in: CGRect(x: 164, y: 164, width: 696, height: 696))

    let bladeColors = [color(0.22, 0.83, 0.72), color(0.96, 0.59, 0.32), color(0.77, 0.91, 0.82)]
    for index in 0..<3 {
        context.saveGState()
        context.translateBy(x: 512, y: 512)
        context.rotate(by: CGFloat(index) * 2 * .pi / 3)
        let blade = CGMutablePath()
        blade.move(to: CGPoint(x: 24, y: -24))
        blade.addCurve(to: CGPoint(x: 54, y: -283), control1: CGPoint(x: 70, y: -73), control2: CGPoint(x: 35, y: -192))
        blade.addCurve(to: CGPoint(x: 136, y: -267), control1: CGPoint(x: 88, y: -332), control2: CGPoint(x: 151, y: -322))
        blade.addCurve(to: CGPoint(x: 77, y: -63), control1: CGPoint(x: 124, y: -213), control2: CGPoint(x: 111, y: -113))
        blade.addCurve(to: CGPoint(x: 24, y: -24), control1: CGPoint(x: 47, y: -33), control2: CGPoint(x: 34, y: -22))
        blade.closeSubpath()
        context.addPath(blade)
        context.setFillColor(bladeColors[index])
        context.fillPath()
        context.restoreGState()
    }

    context.setFillColor(color(0.075, 0.12, 0.15))
    context.fillEllipse(in: CGRect(x: 426, y: 426, width: 172, height: 172))
    context.setFillColor(color(0.98, 0.77, 0.38))
    context.fillEllipse(in: CGRect(x: 472, y: 472, width: 80, height: 80))

    context.setStrokeColor(color(1, 1, 1, 0.12))
    context.setLineWidth(3)
    context.addPath(background)
    context.strokePath()
}

for (filename, size) in iconSizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create icon bitmap at size \(size)")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high
    graphics.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(in: graphics.cgContext)
    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let fileURL = iconsetURL.appendingPathComponent(filename)
    try bitmap.representation(using: .png, properties: [:])!.write(to: fileURL)
}