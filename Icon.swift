// Samotnik — generator ikony aplikacji. Użycie: swift Icon.swift <katalog.iconset>
// Ciemny zaokrąglony kwadrat, zarys planszy w kształcie krzyża z otworami, biała i czarna kula.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func grad(_ c: [CGColor], _ l: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: c as CFArray, locations: l)! }

func marble(_ ctx: CGContext, _ o: CGPoint, _ d: CGFloat, white: Bool) {
    // cień pod kulą
    ctx.drawRadialGradient(grad([rgb(0, 0.55), rgb(0, 0)], [0, 1]),
                           startCenter: CGPoint(x: o.x + d * 0.55, y: o.y + d * 0.38), startRadius: 0,
                           endCenter: CGPoint(x: o.x + d * 0.55, y: o.y + d * 0.38), endRadius: d * 0.62, options: [])
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: o.x, y: o.y, width: d, height: d)); ctx.clip()
    let body = white ? [rgb(0xFBFAF7), rgb(0xE4E1DB), rgb(0xB9B5AE), rgb(0x7E7A74)] : [rgb(0x5C6470), rgb(0x2B3038), rgb(0x14171B), rgb(0x060708)]
    ctx.drawRadialGradient(grad(body, [0, 0.35, 0.78, 1]), startCenter: CGPoint(x: o.x + d * 0.36, y: o.y + d * 0.66), startRadius: 0,
                           endCenter: CGPoint(x: o.x + d * 0.5, y: o.y + d * 0.5), endRadius: d * 0.62, options: [.drawsAfterEndLocation])
    ctx.drawRadialGradient(grad([rgb(0, 0), white ? rgb(0xFFFFFF, 0.3) : rgb(0x8FA6C4, 0.4)], [0, 1]),
                           startCenter: CGPoint(x: o.x + d * 0.45, y: o.y + d * 0.57), startRadius: d * 0.4,
                           endCenter: CGPoint(x: o.x + d * 0.5, y: o.y + d * 0.5), endRadius: d * 0.5, options: [])
    let spec: CGFloat = white ? 0.95 : 0.6
    ctx.drawRadialGradient(grad([rgb(0xFFFFFF, spec), rgb(0xFFFFFF, 0)], [0, 1]), startCenter: CGPoint(x: o.x + d * 0.35, y: o.y + d * 0.7), startRadius: 0,
                           endCenter: CGPoint(x: o.x + d * 0.35, y: o.y + d * 0.7), endRadius: d * 0.17, options: [])
    ctx.restoreGState()
}

func icon(_ px: Int) -> CGImage {
    let s = CGFloat(px) / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    // kafel w siatce ikon macOS (824 px, zaokrąglenie ~185 px) z delikatnym cieniem
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x1A1F25)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.drawLinearGradient(grad([rgb(0x2B323B), rgb(0x141820)], [0, 1]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // plansza w kształcie krzyża z otworami
    let u: CGFloat = 96, c = CGPoint(x: 512, y: 512)
    let arm = CGMutablePath()
    arm.addRoundedRect(in: CGRect(x: c.x - 3.5 * u, y: c.y - 1.5 * u, width: 7 * u, height: 3 * u), cornerWidth: 40, cornerHeight: 40)
    arm.addRoundedRect(in: CGRect(x: c.x - 1.5 * u, y: c.y - 3.5 * u, width: 3 * u, height: 7 * u), cornerWidth: 40, cornerHeight: 40)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0, 0.5))
    ctx.addPath(arm); ctx.setFillColor(rgb(0x262C34)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(arm); ctx.setStrokeColor(rgb(0xFFFFFF, 0.08)); ctx.setLineWidth(4); ctx.strokePath()
    for r in 0..<7 {
        for k in 0..<7 where (2...4).contains(r) || (2...4).contains(k) {
            let x = c.x + CGFloat(k - 3) * u, y = c.y + CGFloat(r - 3) * u
            ctx.addEllipse(in: CGRect(x: x - 22, y: y - 22, width: 44, height: 44))
            ctx.setFillColor(rgb(0x0E1115)); ctx.fillPath()
        }
    }
    marble(ctx, CGPoint(x: 268, y: 430), 300, white: true)
    marble(ctx, CGPoint(x: 466, y: 258), 300, white: false)
    ctx.restoreGState()
    return ctx.makeImage()!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let url = dir.appendingPathComponent("icon_\(name).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, icon(px), nil)
    CGImageDestinationFinalize(dest)
}
