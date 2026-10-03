import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GifCut-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = Double(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 205, yRadius: 205)
        NSGradient(starting: NSColor(red: 0.12, green: 0.52, blue: 0.52, alpha: 1),
                   ending: NSColor(red: 0.26, green: 0.71, blue: 0.61, alpha: 1))!.draw(in: background, angle: 65)
        let frame = NSBezierPath(roundedRect: NSRect(x: 240, y: 300, width: 544, height: 424), xRadius: 52, yRadius: 52)
        NSColor.white.withAlphaComponent(0.94).setStroke()
        frame.lineWidth = 32
        frame.stroke()
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: 452, y: 410))
        triangle.line(to: NSPoint(x: 452, y: 614))
        triangle.line(to: NSPoint(x: 615, y: 512))
        triangle.close()
        NSColor.white.setFill()
        triangle.fill()
        NSColor(red: 0.93, green: 0.81, blue: 0.49, alpha: 1).setFill()
        for x in [224, 754] {
            NSBezierPath(roundedRect: NSRect(x: x, y: 448, width: 46, height: 128), xRadius: 13, yRadius: 13).fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", folder.path, "-o", output.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("无法生成应用图标") }
