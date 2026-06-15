import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func makeContext(_ s: Int) -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGContext(data: nil, width: s, height: s, bitsPerComponent: 8,
                     bytesPerRow: 0, space: cs,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

func roundedRectPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func draw(into ctx: CGContext, size s: CGFloat) {
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // ---- macOS Big Sur style squircle plate with margin + shadow ----
    let margin = s * 0.0977
    let plate = CGRect(x: margin, y: margin, width: s - 2*margin, height: s - 2*margin)
    let corner = plate.width * 0.2247
    let platePath = roundedRectPath(plate, corner)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s*0.012), blur: s*0.03,
                  color: rgb(0,0,0,0.35))
    ctx.addPath(platePath); ctx.setFillColor(rgb(255,255,255)); ctx.fillPath()
    ctx.restoreGState()

    // background gradient (coffee brown)
    ctx.saveGState()
    ctx.addPath(platePath); ctx.clip()
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let grad = CGGradient(colorsSpace: cs,
                          colors: [rgb(122, 78, 46), rgb(58, 36, 20)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: 0, y: plate.maxY),
                           end: CGPoint(x: 0, y: plate.minY),
                           options: [])

    let cx = s/2
    let cream = rgb(250, 243, 228)
    let coffee = rgb(95, 58, 33)

    // ---- saucer ----
    ctx.setShadow(offset: CGSize(width: 0, height: -s*0.006), blur: s*0.02, color: rgb(0,0,0,0.25))
    let saucer = CGRect(x: cx - s*0.245, y: s*0.355, width: s*0.49, height: s*0.085)
    ctx.setFillColor(cream); ctx.fillEllipse(in: saucer)
    ctx.setShadow(offset: .zero, blur: 0, color: rgb(0,0,0,0))

    // ---- handle (C-shape on the right) ----
    ctx.setStrokeColor(cream)
    ctx.setLineWidth(s*0.043)
    ctx.setLineCap(.round)
    let hc = CGPoint(x: cx + s*0.16, y: s*0.555)
    ctx.beginPath()
    ctx.addArc(center: hc, radius: s*0.08,
               startAngle: -.pi/2.1, endAngle: .pi/2.1, clockwise: false)
    ctx.strokePath()

    // ---- cup body (sits on the saucer, smooth rounded bottom) ----
    let topY = s*0.66, botY = s*0.46
    let topHalf = s*0.165, botHalf = s*0.13
    let body = CGMutablePath()
    body.move(to: CGPoint(x: cx - topHalf, y: topY))
    body.addLine(to: CGPoint(x: cx - botHalf, y: botY))
    body.addCurve(to: CGPoint(x: cx + botHalf, y: botY),
                  control1: CGPoint(x: cx - botHalf*0.4, y: botY - s*0.055),
                  control2: CGPoint(x: cx + botHalf*0.4, y: botY - s*0.055))
    body.addLine(to: CGPoint(x: cx + topHalf, y: topY))
    body.closeSubpath()
    ctx.addPath(body); ctx.setFillColor(cream); ctx.fillPath()

    // ---- coffee surface ----
    let surf = CGRect(x: cx - topHalf*0.9, y: topY - s*0.028,
                      width: topHalf*1.8, height: s*0.055)
    ctx.setFillColor(coffee); ctx.fillEllipse(in: surf)

    // ---- steam ----
    ctx.setStrokeColor(rgb(255,255,255,0.85))
    ctx.setLineWidth(s*0.024)
    ctx.setLineCap(.round)
    for dx in [-s*0.06, s*0.06] {
        let baseX = cx + dx
        let p = CGMutablePath()
        p.move(to: CGPoint(x: baseX, y: s*0.70))
        p.addCurve(to: CGPoint(x: baseX, y: s*0.78),
                   control1: CGPoint(x: baseX + s*0.05, y: s*0.725),
                   control2: CGPoint(x: baseX - s*0.05, y: s*0.755))
        p.addCurve(to: CGPoint(x: baseX, y: s*0.85),
                   control1: CGPoint(x: baseX + s*0.05, y: s*0.805),
                   control2: CGPoint(x: baseX - s*0.04, y: s*0.83))
        ctx.addPath(p); ctx.strokePath()
    }
    ctx.restoreGState()
}

func writePNG(_ ctx: CGContext, _ url: URL) {
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/iconout"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// iconset filename -> pixel size
let mapping: [(String, Int)] = [
    ("icon_16x16",      16), ("icon_16x16@2x",   32),
    ("icon_32x32",      32), ("icon_32x32@2x",   64),
    ("icon_128x128",   128), ("icon_128x128@2x",256),
    ("icon_256x256",   256), ("icon_256x256@2x",512),
    ("icon_512x512",   512), ("icon_512x512@2x",1024),
]
for (name, px) in mapping {
    let ctx = makeContext(px)
    draw(into: ctx, size: CGFloat(px))
    writePNG(ctx, URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
// master preview
let m = makeContext(1024); draw(into: m, size: 1024)
writePNG(m, URL(fileURLWithPath: "\(outDir)/preview-1024.png"))
print("wrote icons to \(outDir)")
