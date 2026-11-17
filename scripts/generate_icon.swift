#!/usr/bin/env swift
// Generates the Microscope app icon: a stylized compound microscope on a
// macOS-style rounded square.
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

// MARK: Microscope
// Helpers: fill a rounded rect with a gradient running left→right (cylinder
// shading) or top→bottom.
func fill(_ r: CGRect, radius: CGFloat, _ g: CGGradient, horizontal: Bool = true) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY),
                           end: horizontal ? CGPoint(x: r.maxX, y: r.minY) : CGPoint(x: r.minX, y: r.maxY),
                           options: [])
    ctx.restoreGState()
}
let chrome = gradient([rgb(178, 190, 214), rgb(250, 252, 255), rgb(206, 214, 232), rgb(120, 132, 160)],
                      [0, 0.32, 0.62, 1])
let darkMetal = gradient([rgb(70, 78, 104), rgb(128, 138, 166), rgb(52, 58, 82)], [0, 0.35, 1])
let accent = gradient([rgb(180, 50, 120), rgb(244, 120, 176), rgb(150, 36, 100)], [0, 0.35, 1])
let violet = gradient([rgb(86, 60, 170), rgb(150, 120, 236), rgb(64, 42, 140)], [0, 0.35, 1])

// Soft drop shadow under the whole instrument
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: rgb(0, 0, 0, 0.55))

// Arm: a thick curved spine from the base up behind the tube
let arm = CGMutablePath()
arm.move(to: CGPoint(x: 655, y: 790))
arm.addLine(to: CGPoint(x: 655, y: 560))
arm.addQuadCurve(to: CGPoint(x: 430, y: 330), control: CGPoint(x: 660, y: 340))
ctx.saveGState()
ctx.addPath(arm.copy(strokingWithWidth: 78, lineCap: .round, lineJoin: .round, miterLimit: 10))
ctx.clip()
ctx.drawLinearGradient(chrome, start: CGPoint(x: 600, y: 0), end: CGPoint(x: 720, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

// Base
fill(CGRect(x: 300, y: 770, width: 430, height: 66), radius: 30, darkMetal, horizontal: false)
ctx.restoreGState()

// Illuminator: a squat housing on the base with a lit lens on top.
// (Kept compact and solid; a free-floating glow + light cone read as a
// flower at Dock sizes.)
fill(CGRect(x: 430, y: 712, width: 100, height: 62), radius: 14, darkMetal)
fill(CGRect(x: 446, y: 700, width: 68, height: 18), radius: 8,
     gradient([rgb(255, 244, 200), rgb(255, 214, 120)], [0, 1]), horizontal: false)

// Stage with a glass slide
fill(CGRect(x: 320, y: 600, width: 360, height: 40), radius: 12, darkMetal, horizontal: false)
fill(CGRect(x: 320, y: 600, width: 360, height: 8), radius: 4,
     gradient([rgb(170, 180, 206), rgb(120, 130, 160)], [0, 1]), horizontal: false)
ctx.setFillColor(rgb(150, 220, 245, 0.85))
ctx.fill(CGRect(x: 396, y: 588, width: 158, height: 14))
ctx.setFillColor(rgb(244, 120, 176, 0.95))
ctx.fillEllipse(in: CGRect(x: 458, y: 589, width: 34, height: 12))

// Focus knob on the arm
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 12, color: rgb(0, 0, 0, 0.4))
ctx.addEllipse(in: CGRect(x: 612, y: 470, width: 88, height: 88))
ctx.clip()
ctx.drawLinearGradient(violet, start: CGPoint(x: 612, y: 470), end: CGPoint(x: 700, y: 558), options: [])
ctx.restoreGState()
ctx.setFillColor(rgb(230, 222, 255, 0.9))
ctx.fillEllipse(in: CGRect(x: 640, y: 498, width: 32, height: 32))

// Optical tube, tilted with the eyepiece leaning away from the arm.
// Local frame: origin at the objective tip, tube runs up the −y axis.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 8, height: 14), blur: 26, color: rgb(0, 0, 0, 0.45))
ctx.translateBy(x: 478, y: 556)
ctx.rotate(by: -24 * .pi / 180)
fill(CGRect(x: -22, y: -64, width: 44, height: 64), radius: 8, darkMetal)          // objective
fill(CGRect(x: -26, y: -20, width: 52, height: 10), radius: 4, accent)             // objective colour band
fill(CGRect(x: -58, y: -112, width: 116, height: 54), radius: 18, violet)          // nosepiece
fill(CGRect(x: -46, y: -330, width: 92, height: 226), radius: 16, chrome)          // body tube
fill(CGRect(x: -49, y: -262, width: 98, height: 22), radius: 6, accent)            // accent ring
fill(CGRect(x: -32, y: -396, width: 64, height: 72), radius: 10, chrome)           // eyepiece
fill(CGRect(x: -42, y: -412, width: 84, height: 26), radius: 10, darkMetal)        // eyecup
ctx.restoreGState()

// MARK: Write PNG
let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
