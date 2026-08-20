#!/usr/bin/env swift
// Генератор иконки приложения.
//
// Иконка лежит в репозитории как набор PNG, но собирается этим скриптом:
// картинку непонятного происхождения в проект кладут один раз, а потом никто
// не знает, как её поправить.
//
//   swift tools/make-icon.swift Cleaner/Resources/Assets.xcassets/AppIcon.appiconset

import AppKit

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Cleaner/Resources/Assets.xcassets/AppIcon.appiconset"

// Синий градиент и белая метёлка: без затей, зато читается в 16 пикселей.
let top = NSColor(srgbRed: 0.36, green: 0.66, blue: 1.00, alpha: 1)
let bottom = NSColor(srgbRed: 0.04, green: 0.36, blue: 0.82, alpha: 1)

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let result = NSImage(size: image.size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: image.size))
    color.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    result.unlockFocus()
    return result
}

func render(pixels: Int) -> Data {
    let side = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("не удалось создать буфер \(pixels)px") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Скруглённый квадрат в духе системных иконок.
    let inset = side * 0.06
    let box = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = box.width * 0.2237
    let squircle = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
    squircle.addClip()
    NSGradient(starting: top, ending: bottom)?.draw(in: box, angle: -90)

    // Глиф берём из SF Symbols: рисовать метёлку вручную — заведомо хуже.
    if let symbol = NSImage(systemSymbolName: "wand.and.sparkles", accessibilityDescription: nil),
       let configured = symbol.withSymbolConfiguration(
           .init(pointSize: side * 0.46, weight: .medium)) {
        let glyph = tinted(configured, .white)
        let target = NSRect(
            x: (side - glyph.size.width) / 2,
            y: (side - glyph.size.height) / 2,
            width: glyph.size.width,
            height: glyph.size.height
        )
        glyph.draw(in: target)
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("не удалось получить PNG \(pixels)px")
    }
    return data
}

struct Entry {
    let base: Int
    let scale: Int
    var pixels: Int { base * scale }
    var name: String { "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png" }
    var json: String {
        """
            {
              "size" : "\(base)x\(base)",
              "idiom" : "mac",
              "filename" : "\(name)",
              "scale" : "\(scale)x"
            }
        """
    }
}

let entries = [16, 32, 128, 256, 512].flatMap { base in
    [Entry(base: base, scale: 1), Entry(base: base, scale: 2)]
}

let directory = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for entry in entries {
    try render(pixels: entry.pixels).write(to: directory.appendingPathComponent(entry.name))
    print("  \(entry.name)\t\(entry.pixels)×\(entry.pixels)")
}

let contents = """
{
  "images" : [
\(entries.map(\.json).joined(separator: ",\n"))
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
"""
try contents.write(to: directory.appendingPathComponent("Contents.json"),
                   atomically: true, encoding: .utf8)
print("  Contents.json")
