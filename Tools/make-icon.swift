// PortHawk app icon generator: paper-ledger style.
// Rounded paper square + a blue-ink double chevron (the hawk's wings) + a
// vermilion dot, the same symbol as the menu bar alert.
//
// The artwork is drawn in a 1024x1024 space and then scaled onto the body of
// Apple's macOS icon grid: an 824x824 rounded square centred in the 1024 canvas,
// leaving 100px of transparent margin on every side. Drawing to the full canvas
// instead makes the icon read as oversized next to every other app in the Dock.
//
// Run: swift Tools/make-icon.swift <output directory>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let S: CGFloat = 1024

/// Apple's macOS icon grid (Big Sur and later): the icon body occupies 824 of
/// the 1024 canvas, so 100px of margin all round. Corner radius follows at
/// roughly 22.4% of the body.
let inset: CGFloat = 100
let body = S - inset * 2
let bodyScale = body / S

func paper(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Map the drawing space onto the icon body. Every coordinate below can then
// stay expressed against the full 1024 design, and the whole artwork lands
// inside the grid with its proportions intact.
ctx.translateBy(x: inset, y: inset)
ctx.scaleBy(x: bodyScale, y: bodyScale)

// Paper squircle. The radius is 22.5% of the body, matching the grid.
let paperRect = NSRect(x: 0, y: 0, width: S, height: S)
let squircle = NSBezierPath(roundedRect: paperRect, xRadius: S * 0.225, yRadius: S * 0.225)
paper(0xF7F3E9).setFill()
squircle.fill()

// Ledger rules: three hairlines across the top, echoing a ledger header
paper(0x1F1E1A, 0.14).setStroke()
for i in 0..<3 {
    let y = S * (0.82 - CGFloat(i) * 0.055)
    let line = NSBezierPath()
    line.move(to: NSPoint(x: S * 0.16, y: y))
    line.line(to: NSPoint(x: S * 0.84, y: y))
    line.lineWidth = 6
    line.stroke()
}

// Chevron: two thick right-pointing arrows, front stroke in full blue ink and
// the rear one faded, with rounded caps
func chevron(_ color: NSColor, _ offsetX: CGFloat, _ width: CGFloat) {
    color.setStroke()
    color.setFill()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: S * 0.30 + offsetX, y: S * 0.68))
    path.line(to: NSPoint(x: S * 0.55 + offsetX, y: S * 0.47))
    path.line(to: NSPoint(x: S * 0.30 + offsetX, y: S * 0.26))
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}
chevron(paper(0x2D4B6F, 0.35), S * 0.06, 92)   // rear wing (faded)
chevron(paper(0x2D4B6F), 0, 108)               // front wing (blue ink)

// Vermilion dot: the menu bar alert symbol, sitting ahead of the beak
paper(0xA3321C).setFill()
NSBezierPath(ovalIn: NSRect(x: S * 0.68 - 54, y: S * 0.47 - 54, width: 108, height: 108)).fill()

image.unlockFocus()

// Export PNG
func bitmap(_ image: NSImage) -> NSBitmapImageRep? {
    guard let tiff = image.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)
}

func writePNG(_ image: NSImage, _ path: String) -> Bool {
    guard let rep = bitmap(image),
          let png = rep.representation(using: .png, properties: [:]) else { return false }
    try? png.write(to: URL(fileURLWithPath: path))
    return true
}

/// Measure how much of the canvas the opaque body covers, so the grid
/// conformance is checked rather than assumed.
func bodyCoverage(_ image: NSImage) -> Double? {
    guard let rep = bitmap(image) else { return nil }
    let w = rep.pixelsWide, h = rep.pixelsHigh
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            // Fully opaque pixels only, so an antialiased edge does not count.
            if c.alphaComponent >= 0.98 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX else { return nil }
    return Double(maxX - minX + 1) / Double(w) * 100
}

let base = outDir.hasSuffix("/") ? outDir : outDir + "/"
if !writePNG(image, base + "icon_1024.png") { exit(1) }

let coverage = bodyCoverage(image) ?? 0
print("icon master written -> \(base)icon_1024.png")
print(String(format: "icon body covers %.1f%% of the canvas (Apple grid expects ~80.5%%)", coverage))

// Apple's grid is 824/1024 = 80.47%. Fail loudly on drift so a future tweak
// cannot silently reintroduce an oversized icon.
if abs(coverage - 80.5) > 1.5 {
    FileHandle.standardError.write(
        "!! icon body coverage \(coverage)% is outside the macOS icon grid\n".data(using: .utf8)!)
    exit(1)
}
