// Generates the app icon and the menu bar icon into the asset catalog, from
// the repo root:
//   swift scripts/generate-icons.swift
// macOS only, no dependencies. Ported from the Electron app's
// scripts/generate-icons.swift, which drew the same icons.
//
// AppIcon.appiconset: MoneyFace.png is 433x480, the face being the 433px
// circle at the top with the tongue hanging below. The circle is mapped onto
// a square with the elliptical grid mapping (sampled ~3px inside the rim), so
// the round face becomes a rounded square while its centre barely moves and
// the tongue runs off the bottom edge. That square sits on the macOS icon
// grid (824 of 1024 px, with the transparent padding and soft shadow macOS
// draws icons with).
//
// MenuBarIcon.imageset: a ring with eyes and a smile, 16 pt, black with
// alpha, as a template image: macOS tints it for the light or dark menu bar.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Millisalary/Assets.xcassets")
let source = assets.appendingPathComponent("MoneyFace.imageset/MoneyFace.png")
guard FileManager.default.fileExists(atPath: source.path) else {
    fatalError("run from the repo root: \(source.path) not found")
}

let canvas = 1024
let body = 824
let cornerRadius = Double(body) * 0.225
let faceCenter = (x: 216.5, y: 216.5)
let faceRadius = 216.5 - 3.0

func loadPixels(_ url: URL) -> (data: [UInt8], width: Int, height: Int) {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { fatalError("can't read \(url.path)") }
    let width = image.width, height = image.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(
        data: &data, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (data, width, height)
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("can't write \(url.path)") }
}

func writeContents(_ json: String, in folder: URL) {
    try! json.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

func makeContext(_ size: Int) -> CGContext {
    CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// MARK: - App icon

func renderBody() -> CGImage {
    let face = loadPixels(source)
    var pixels = [UInt8](repeating: 0, count: body * body * 4)

    func sample(_ x: Double, _ y: Double) -> [Double] {
        let fx = min(max(x, 0), Double(face.width - 1)), fy = min(max(y, 0), Double(face.height - 1))
        let x0 = Int(fx), y0 = Int(fy)
        let x1 = min(x0 + 1, face.width - 1), y1 = min(y0 + 1, face.height - 1)
        let tx = fx - Double(x0), ty = fy - Double(y0)
        var result = [Double](repeating: 0, count: 4)
        for channel in 0..<4 {
            func at(_ px: Int, _ py: Int) -> Double { Double(face.data[(py * face.width + px) * 4 + channel]) }
            let top = at(x0, y0) * (1 - tx) + at(x1, y0) * tx
            let bottom = at(x0, y1) * (1 - tx) + at(x1, y1) * tx
            result[channel] = top * (1 - ty) + bottom * ty
        }
        return result
    }

    for py in 0..<body {
        for px in 0..<body {
            let u = (Double(px) + 0.5) / Double(body) * 2 - 1
            let v = (Double(py) + 0.5) / Double(body) * 2 - 1
            // square -> disc (elliptical grid mapping)
            let dx = u * (1 - v * v / 2).squareRoot()
            let dy = v * (1 - u * u / 2).squareRoot()
            let rgba = sample(faceCenter.x + dx * faceRadius, faceCenter.y + dy * faceRadius)
            for channel in 0..<4 {
                pixels[(py * body + px) * 4 + channel] = UInt8(min(255, max(0, rgba[channel].rounded())))
            }
        }
    }

    let context = CGContext(
        data: &pixels, width: body, height: body, bitsPerComponent: 8, bytesPerRow: body * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

func renderIcon() -> CGImage {
    let context = makeContext(canvas)
    let inset = Double(canvas - body) / 2
    let rect = CGRect(x: inset, y: inset, width: Double(body), height: Double(body))
    let shape = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // The soft shadow macOS icons carry, below the body
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -12), blur: 24,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.draw(renderBody(), in: rect)
    context.restoreGState()

    return context.makeImage()!
}

func scaled(_ image: CGImage, to size: Int) -> CGImage {
    let context = makeContext(size)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()!
}

func writeAppIcon(_ icon: CGImage) {
    let folder = assets.appendingPathComponent("AppIcon.appiconset")
    try? FileManager.default.removeItem(at: folder)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    var images: [String] = []
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
            writePNG(scaled(icon, to: base * scale), to: folder.appendingPathComponent(name))
            images.append("""
                    {
                      "filename" : "\(name)",
                      "idiom" : "mac",
                      "scale" : "\(scale)x",
                      "size" : "\(base)x\(base)"
                    }
                """)
        }
    }
    writeContents("""
        {
          "images" : [
        \(images.joined(separator: ",\n"))
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }

        """, in: folder)
}

// MARK: - Menu bar icon

func renderMenuBarIcon(points: Int, scale: Int) -> CGImage {
    let size = points * scale
    let context = makeContext(size)
    let s = Double(size)
    context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.setLineCap(.round)

    // The face: a ring, two eyes, a smile (y is up in CoreGraphics)
    let line = 1.3 * Double(scale)
    context.setLineWidth(line)
    context.strokeEllipse(in: CGRect(x: line / 2 + 0.5, y: line / 2 + 0.5, width: s - line - 1, height: s - line - 1))

    let eye = 1.1 * Double(scale)
    for x in [0.36, 0.64] {
        context.fillEllipse(in: CGRect(x: x * s - eye, y: 0.60 * s - eye, width: eye * 2, height: eye * 2))
    }
    context.setLineWidth(1.1 * Double(scale))
    context.addArc(center: CGPoint(x: 0.5 * s, y: 0.5 * s), radius: 0.24 * s, startAngle: .pi * 1.18, endAngle: .pi * 1.82, clockwise: false)
    context.strokePath()

    return context.makeImage()!
}

func writeMenuBarIcon() {
    let folder = assets.appendingPathComponent("MenuBarIcon.imageset")
    try? FileManager.default.removeItem(at: folder)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    writePNG(renderMenuBarIcon(points: 16, scale: 1), to: folder.appendingPathComponent("MenuBarIcon.png"))
    writePNG(renderMenuBarIcon(points: 16, scale: 2), to: folder.appendingPathComponent("MenuBarIcon@2x.png"))
    writeContents("""
        {
          "images" : [
            {
              "filename" : "MenuBarIcon.png",
              "idiom" : "mac",
              "scale" : "1x"
            },
            {
              "filename" : "MenuBarIcon@2x.png",
              "idiom" : "mac",
              "scale" : "2x"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          },
          "properties" : {
            "template-rendering-intent" : "template"
          }
        }

        """, in: folder)
}

writeAppIcon(renderIcon())
writeMenuBarIcon()
print("wrote AppIcon.appiconset and MenuBarIcon.imageset in \(assets.path)")
