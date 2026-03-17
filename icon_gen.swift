import Cocoa
import CoreGraphics

// Generate a 1024x1024 app icon PNG for Claude Monitor
// Draws "CC" text over a gradient background with rounded corners

let size = 1024
let cgSize = CGSize(width: size, height: size)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}

let rect = CGRect(origin: .zero, size: cgSize)

// Rounded rectangle clip (macOS icon shape)
let cornerRadius: CGFloat = CGFloat(size) * 0.22
let path = CGMutablePath()
path.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
ctx.addPath(path)
ctx.clip()

// Gradient background: deep purple to warm orange
let gradientColors = [
    CGColor(red: 0.35, green: 0.15, blue: 0.65, alpha: 1.0),
    CGColor(red: 0.85, green: 0.45, blue: 0.25, alpha: 1.0)
] as CFArray
let locations: [CGFloat] = [0.0, 1.0]
guard let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations) else {
    fputs("Failed to create gradient\n", stderr)
    exit(1)
}
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: CGFloat(size)),
    end: CGPoint(x: CGFloat(size), y: 0),
    options: []
)

// Draw "CC" text centered
let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = nsCtx

let fontSize: CGFloat = CGFloat(size) * 0.42
let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
let text = "CC" as NSString
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white
]
let textSize = text.size(withAttributes: attrs)
let textOrigin = CGPoint(
    x: (CGFloat(size) - textSize.width) / 2.0,
    y: (CGFloat(size) - textSize.height) / 2.0
)
text.draw(at: textOrigin, withAttributes: attrs)

NSGraphicsContext.current = nil

// Save as PNG
guard let image = ctx.makeImage() else {
    fputs("Failed to create image\n", stderr)
    exit(1)
}

let outputPath: String
if CommandLine.arguments.count > 1 {
    outputPath = CommandLine.arguments[1]
} else {
    outputPath = "AppIcon.png"
}

let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("Failed to create image destination\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("Failed to write PNG\n", stderr)
    exit(1)
}

print("Generated \(outputPath) (\(size)x\(size))")
