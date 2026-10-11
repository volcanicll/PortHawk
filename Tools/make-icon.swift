// PortHawk 应用图标生成：纸面账簿风
// 纸色圆角方 + 墨蓝鹰形双箭（hawk 谐音）+ 朱砂圆点（菜单栏告警点的同源符号）
// 运行：swift Tools/make-icon.swift <输出目录>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let S: CGFloat = 1024

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

// 纸面 squircle
let paperRect = NSRect(x: 0, y: 0, width: S, height: S)
let squircle = NSBezierPath(roundedRect: paperRect, xRadius: S * 0.225, yRadius: S * 0.225)
paper(0xF7F3E9).setFill()
squircle.fill()

// 账簿横格：上部三道细墨线（呼应账簿页眉）
paper(0x1F1E1A, 0.14).setStroke()
for i in 0..<3 {
    let y = S * (0.82 - CGFloat(i) * 0.055)
    let line = NSBezierPath()
    line.move(to: NSPoint(x: S * 0.16, y: y))
    line.line(to: NSPoint(x: S * 0.84, y: y))
    line.lineWidth = 6
    line.stroke()
}

// 鹰形双箭：两道右指粗箭，前羽墨蓝、后羽淡蓝，线帽圆
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
chevron(paper(0x2D4B6F, 0.35), S * 0.06, 92)   // 后羽（淡）
chevron(paper(0x2D4B6F), 0, 108)               // 前羽（墨蓝）

// 朱砂圆点：菜单栏告警点的同源符号，落在鹰喙前方
paper(0xA3321C).setFill()
NSBezierPath(ovalIn: NSRect(x: S * 0.68 - 54, y: S * 0.47 - 54, width: 108, height: 108)).fill()

image.unlockFocus()

// 导出 PNG
func writePNG(_ image: NSImage, _ path: String) -> Bool {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return false }
    try? png.write(to: URL(fileURLWithPath: path))
    return true
}

let base = outDir.hasSuffix("/") ? outDir : outDir + "/"
if !writePNG(image, base + "icon_1024.png") { exit(1) }
print("icon master written → \(base)icon_1024.png")
