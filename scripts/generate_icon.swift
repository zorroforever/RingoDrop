#!/usr/bin/env swift
//
//  generate_icon.swift
//  Generates a 1024x1024 macOS Liquid Glass iconset for RingoDrop (りんご雫)
//

import AppKit
import CoreGraphics
import Foundation

func drawRingoDropIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let scale = size / 1024.0
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)

    // 1. macOS Squircle Base Geometry (824x824 centered in 1024x1024)
    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let cornerRadius: CGFloat = 185.0
    let squirclePath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Outer Drop Shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -22),
        blur: 42,
        color: NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.14, alpha: 0.65).cgColor
    )
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.24, alpha: 1.0).setFill()
    squirclePath.fill()
    ctx.restoreGState()

    // Clip to Squircle
    squirclePath.addClip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // 2. Deep Twilight Navy + Sakura & Sora Aurora Background
    let bgColors = [
        NSColor(calibratedRed: 0.14, green: 0.11, blue: 0.30, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.26, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.17, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(
            bgGrad,
            start: CGPoint(x: 100, y: 924),
            end: CGPoint(x: 924, y: 100),
            options: []
        )
    }

    // Sakura Pink Top-Left Glow
    let sakuraColors = [
        NSColor(calibratedRed: 0.98, green: 0.44, blue: 0.68, alpha: 0.82).cgColor,
        NSColor(calibratedRed: 0.98, green: 0.44, blue: 0.68, alpha: 0.0).cgColor
    ] as CFArray
    if let sakuraGrad = CGGradient(colorsSpace: colorSpace, colors: sakuraColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            sakuraGrad,
            startCenter: CGPoint(x: 240, y: 780),
            startRadius: 10,
            endCenter: CGPoint(x: 240, y: 780),
            endRadius: 520,
            options: []
        )
    }

    // Sora Cyan Bottom-Right Glow
    let soraColors = [
        NSColor(calibratedRed: 0.25, green: 0.85, blue: 1.0, alpha: 0.85).cgColor,
        NSColor(calibratedRed: 0.25, green: 0.85, blue: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    if let soraGrad = CGGradient(colorsSpace: colorSpace, colors: soraColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            soraGrad,
            startCenter: CGPoint(x: 780, y: 230),
            startRadius: 10,
            endCenter: CGPoint(x: 780, y: 230),
            endRadius: 540,
            options: []
        )
    }

    // 3. Translucent Floating Glass Circle Plate Behind Droplet
    let glassPlateRect = CGRect(x: 212, y: 212, width: 600, height: 600)
    let glassPlatePath = NSBezierPath(ovalIn: glassPlateRect)
    NSColor(calibratedWhite: 1.0, alpha: 0.08).setFill()
    glassPlatePath.fill()
    NSColor(calibratedWhite: 1.0, alpha: 0.24).setStroke()
    glassPlatePath.lineWidth = 3.0
    glassPlatePath.stroke()

    // 4. Main Crystal Ringo Dewdrop (りんご雫) Shape
    let dropPath = NSBezierPath()
    // Tip at top (512, 790), rounded belly at bottom (center 512, 430, radius ~215)
    dropPath.move(to: CGPoint(x: 512, y: 795))
    dropPath.curve(
        to: CGPoint(x: 726, y: 430),
        controlPoint1: CGPoint(x: 595, y: 675),
        controlPoint2: CGPoint(x: 726, y: 555)
    )
    dropPath.curve(
        to: CGPoint(x: 512, y: 220),
        controlPoint1: CGPoint(x: 726, y: 305),
        controlPoint2: CGPoint(x: 632, y: 220)
    )
    dropPath.curve(
        to: CGPoint(x: 298, y: 430),
        controlPoint1: CGPoint(x: 392, y: 220),
        controlPoint2: CGPoint(x: 298, y: 305)
    )
    dropPath.curve(
        to: CGPoint(x: 512, y: 795),
        controlPoint1: CGPoint(x: 298, y: 555),
        controlPoint2: CGPoint(x: 429, y: 675)
    )
    dropPath.close()

    // Shadow under Crystal Droplet
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -18),
        blur: 36,
        color: NSColor(calibratedRed: 0.05, green: 0.03, blue: 0.18, alpha: 0.55).cgColor
    )
    NSColor(calibratedRed: 0.96, green: 0.45, blue: 0.70, alpha: 0.95).setFill()
    dropPath.fill()
    ctx.restoreGState()

    // Fill Crystal Droplet with Liquid Glass Gradient (Sakura Pink -> Violet -> Sora Cyan)
    ctx.saveGState()
    dropPath.addClip()
    let dropColors = [
        NSColor(calibratedRed: 1.0, green: 0.56, blue: 0.76, alpha: 0.96).cgColor,
        NSColor(calibratedRed: 0.68, green: 0.48, blue: 0.98, alpha: 0.92).cgColor,
        NSColor(calibratedRed: 0.28, green: 0.84, blue: 1.0, alpha: 0.96).cgColor
    ] as CFArray
    if let dropGrad = CGGradient(colorsSpace: colorSpace, colors: dropColors, locations: [0.0, 0.52, 1.0]) {
        ctx.drawLinearGradient(
            dropGrad,
            start: CGPoint(x: 340, y: 760),
            end: CGPoint(x: 680, y: 230),
            options: []
        )
    }

    // Inner Left Specular Glass Highlight Crescent
    let crescentPath = NSBezierPath()
    crescentPath.move(to: CGPoint(x: 475, y: 710))
    crescentPath.curve(
        to: CGPoint(x: 342, y: 435),
        controlPoint1: CGPoint(x: 410, y: 620),
        controlPoint2: CGPoint(x: 342, y: 525)
    )
    crescentPath.curve(
        to: CGPoint(x: 435, y: 285),
        controlPoint1: CGPoint(x: 342, y: 355),
        controlPoint2: CGPoint(x: 380, y: 300)
    )
    crescentPath.curve(
        to: CGPoint(x: 388, y: 445),
        controlPoint1: CGPoint(x: 395, y: 330),
        controlPoint2: CGPoint(x: 388, y: 385)
    )
    crescentPath.curve(
        to: CGPoint(x: 475, y: 710),
        controlPoint1: CGPoint(x: 388, y: 530),
        controlPoint2: CGPoint(x: 432, y: 625)
    )
    crescentPath.close()
    NSColor(calibratedWhite: 1.0, alpha: 0.48).setFill()
    crescentPath.fill()
    ctx.restoreGState()

    // Crystal Droplet Specular Rim Border
    NSColor(calibratedWhite: 1.0, alpha: 0.82).setStroke()
    dropPath.lineWidth = 6.5
    dropPath.stroke()

    // 5. Cute Glowing Ringo Leaf at Top-Right of Droplet Tip
    let leafPath = NSBezierPath()
    leafPath.move(to: CGPoint(x: 535, y: 785))
    leafPath.curve(
        to: CGPoint(x: 655, y: 845),
        controlPoint1: CGPoint(x: 555, y: 840),
        controlPoint2: CGPoint(x: 605, y: 855)
    )
    leafPath.curve(
        to: CGPoint(x: 535, y: 785),
        controlPoint1: CGPoint(x: 635, y: 790),
        controlPoint2: CGPoint(x: 585, y: 770)
    )
    leafPath.close()
    NSColor(calibratedRed: 0.55, green: 0.98, blue: 0.84, alpha: 0.95).setFill()
    leafPath.fill()
    NSColor(calibratedWhite: 1.0, alpha: 0.85).setStroke()
    leafPath.lineWidth = 4.0
    leafPath.stroke()

    // 6. Crisp White Download Arrow & Apple Silhouette Inside Droplet Belly
    let arrowConfig = NSImage.SymbolConfiguration(pointSize: 195, weight: .bold)
    if let symbol = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(arrowConfig)
    {
        let symSize = symbol.size
        let targetRect = CGRect(
            x: 512 - symSize.width / 2,
            y: 420 - symSize.height / 2,
            width: symSize.width,
            height: symSize.height
        )
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -8),
            blur: 18,
            color: NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.30, alpha: 0.45).cgColor
        )
        // Tint symbol white
        let tinted = NSImage(size: symSize)
        tinted.lockFocus()
        NSColor.white.set()
        let imgRect = CGRect(origin: .zero, size: symSize)
        symbol.draw(in: imgRect)
        imgRect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: targetRect)
        ctx.restoreGState()
    }

    // 7. Cute Floating Glass Dew Bubbles
    let bubbles: [(CGFloat, CGFloat, CGFloat)] = [
        (265, 670, 26),
        (755, 635, 34),
        (715, 725, 16),
        (290, 275, 20)
    ]
    for (bx, by, br) in bubbles {
        let bRect = CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)
        let bPath = NSBezierPath(ovalIn: bRect)
        NSColor(calibratedWhite: 1.0, alpha: 0.25).setFill()
        bPath.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.68).setStroke()
        bPath.lineWidth = 2.5
        bPath.stroke()
    }

    // 8. Squircle Top Glass Rim Light & Border
    let rimPath = NSBezierPath(roundedRect: iconRect.insetBy(dx: 3, dy: 3), xRadius: cornerRadius - 3, yRadius: cornerRadius - 3)
    NSColor(calibratedWhite: 1.0, alpha: 0.42).setStroke()
    rimPath.lineWidth = 6.0
    rimPath.stroke()

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to url: URL, pixelSize: Int) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "IconGen", code: 1)
    }
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(
        in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 2)
    }
    try pngData.write(to: url)
}

let args = CommandLine.arguments
let outputIconsetDir = args.count > 1 ? args[1] : "AppIcon.iconset"
let iconsetURL = URL(fileURLWithPath: outputIconsetDir)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let masterImage = drawRingoDropIcon(size: 1024)
let specs: [(String, Int)] = [
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

for (filename, px) in specs {
    try savePNG(masterImage, to: iconsetURL.appendingPathComponent(filename), pixelSize: px)
}
print("✅ Generated RingoDrop iconset at \(outputIconsetDir)")
