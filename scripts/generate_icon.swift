#!/usr/bin/env swift
// Generates the Microscope app icon: a brightfield "view through the eyepiece"
// with stained cells and a measuring reticle, on a macOS-style rounded square.
//
// Usage: swift scripts/generate_icon.swift <output.png>
// Everything is procedural and deterministic; tweak the constants and re-run
// scripts/make_icon.sh to rebuild Resources/AppIcon.icns.

import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-source.png")

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: locations)!
}

let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Flip so y grows downward (easier to reason about layout).
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// MARK: Background tile (Big Sur grid: 824pt tile, 100pt margin)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(20, 28, 44)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(38, 44, 74), rgb(14, 18, 34)], [0, 1]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
ctx.restoreGState()

// MARK: Eyepiece ring
let center = CGPoint(x: 512, y: 512)
let fieldR: CGFloat = 292
let ringW: CGFloat = 34
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: rgb(0, 0, 0, 0.55))
ctx.addEllipse(in: CGRect(x: center.x - fieldR - ringW, y: center.y - fieldR - ringW,
                          width: 2 * (fieldR + ringW), height: 2 * (fieldR + ringW)))
ctx.setFillColor(rgb(60, 66, 84)); ctx.fillPath()
ctx.restoreGState()
// brushed-metal ring: linear gradient clipped to the annulus
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - fieldR - ringW, y: center.y - fieldR - ringW,
                          width: 2 * (fieldR + ringW), height: 2 * (fieldR + ringW)))
ctx.addEllipse(in: CGRect(x: center.x - fieldR, y: center.y - fieldR, width: 2 * fieldR, height: 2 * fieldR))
ctx.clip(using: .evenOdd)
ctx.drawLinearGradient(gradient([rgb(214, 220, 232), rgb(120, 128, 146), rgb(70, 76, 94), rgb(170, 178, 194)],
                                [0, 0.45, 0.7, 1]),
                       start: CGPoint(x: 260, y: 190), end: CGPoint(x: 760, y: 840), options: [])
ctx.restoreGState()

// MARK: Field of view (brightfield illumination)
let field = CGPath(ellipseIn: CGRect(x: center.x - fieldR, y: center.y - fieldR, width: 2 * fieldR, height: 2 * fieldR),
                   transform: nil)
ctx.saveGState()
ctx.addPath(field); ctx.clip()
ctx.drawRadialGradient(gradient([rgb(255, 251, 240), rgb(250, 236, 214), rgb(232, 206, 186)], [0, 0.65, 1]),
                       startCenter: CGPoint(x: 470, y: 450), startRadius: 0,
                       endCenter: center, endRadius: fieldR, options: [.drawsAfterEndLocation])

// Cells: (center x, y, radius x, radius y, rotation deg, nucleus offset x, y, nucleus radius)
struct Cell { let x, y, rx, ry, rot, nx, ny, nr: CGFloat }
let cells: [Cell] = [
    Cell(x: 395, y: 360, rx: 92, ry: 74, rot: -18, nx: 14, ny: 6, nr: 30),
    Cell(x: 590, y: 330, rx: 84, ry: 70, rot: 24, nx: -10, ny: 12, nr: 27),
    Cell(x: 700, y: 500, rx: 70, ry: 88, rot: 8, nx: 6, ny: -14, nr: 26),
    Cell(x: 505, y: 520, rx: 98, ry: 82, rot: -6, nx: -16, ny: 4, nr: 34),
    Cell(x: 330, y: 560, rx: 78, ry: 92, rot: 30, nx: 12, ny: 10, nr: 28),
    Cell(x: 440, y: 720, rx: 90, ry: 70, rot: -24, nx: -6, ny: -10, nr: 29),
    Cell(x: 640, y: 700, rx: 86, ry: 76, rot: 16, nx: 10, ny: 8, nr: 30),
    Cell(x: 790, y: 330, rx: 70, ry: 64, rot: 0, nx: 0, ny: 0, nr: 24),
    Cell(x: 230, y: 400, rx: 66, ry: 80, rot: 12, nx: 0, ny: 0, nr: 24),
]
for c in cells {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: c.rot * .pi / 180)
    let body = CGRect(x: -c.rx, y: -c.ry, width: 2 * c.rx, height: 2 * c.ry)
    // cytoplasm: soft pink with a lighter centre
    ctx.saveGState()
    ctx.addEllipse(in: body); ctx.clip()
    ctx.drawRadialGradient(gradient([rgb(246, 196, 214, 0.75), rgb(226, 132, 170, 0.85)], [0, 1]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero,
                           endRadius: max(c.rx, c.ry), options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    // membrane
    ctx.addEllipse(in: body.insetBy(dx: 2, dy: 2))
    ctx.setStrokeColor(rgb(176, 64, 120, 0.9)); ctx.setLineWidth(6); ctx.strokePath()
    // nucleus with nucleolus
    let n = CGRect(x: c.nx - c.nr, y: c.ny - c.nr, width: 2 * c.nr, height: 2 * c.nr)
    ctx.saveGState()
    ctx.addEllipse(in: n); ctx.clip()
    ctx.drawRadialGradient(gradient([rgb(132, 92, 196), rgb(74, 42, 130)], [0, 1]),
                           startCenter: CGPoint(x: c.nx - c.nr * 0.3, y: c.ny - c.nr * 0.3), startRadius: 0,
                           endCenter: CGPoint(x: c.nx, y: c.ny), endRadius: c.nr, options: [])
    ctx.restoreGState()
    ctx.addEllipse(in: CGRect(x: c.nx + c.nr * 0.15, y: c.ny - c.nr * 0.35, width: c.nr * 0.36, height: c.nr * 0.36))
    ctx.setFillColor(rgb(40, 20, 80, 0.85)); ctx.fillPath()
    ctx.restoreGState()
}

// Reticle: crosshair with a graduated scale on the horizontal axis
let ink = rgb(30, 34, 52, 0.72)
ctx.setStrokeColor(ink)
ctx.setLineWidth(4)
ctx.move(to: CGPoint(x: center.x - fieldR, y: center.y)); ctx.addLine(to: CGPoint(x: center.x + fieldR, y: center.y))
ctx.move(to: CGPoint(x: center.x, y: center.y - fieldR)); ctx.addLine(to: CGPoint(x: center.x, y: center.y + fieldR))
ctx.strokePath()
let step: CGFloat = 24
for i in -10...10 where i != 0 {
    let x = center.x + CGFloat(i) * step
    let h: CGFloat = i % 5 == 0 ? 28 : 14
    ctx.move(to: CGPoint(x: x, y: center.y - h)); ctx.addLine(to: CGPoint(x: x, y: center.y + h))
}
ctx.setLineWidth(3.5); ctx.strokePath()

// Vignette at the edge of the field
ctx.drawRadialGradient(gradient([rgb(0, 0, 0, 0), rgb(0, 0, 0, 0), rgb(40, 20, 30, 0.45)], [0, 0.78, 1]),
                       startCenter: center, startRadius: 0, endCenter: center, endRadius: fieldR, options: [])
// Glint on the "cover glass"
ctx.drawRadialGradient(gradient([rgb(255, 255, 255, 0.35), rgb(255, 255, 255, 0)], [0, 1]),
                       startCenter: CGPoint(x: 400, y: 330), startRadius: 0,
                       endCenter: CGPoint(x: 400, y: 330), endRadius: 170, options: [])
ctx.restoreGState()

// MARK: Write PNG
let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
