import AppKit
import WTManagerKit

// Bakes the app icon from the same sprite the menu bar draws, so the icon can
// never show a character the app no longer has.
//
// usage: MakeIcon <mascot.json> <output-dir>

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: MakeIcon <mascot.json> <out-dir>\n".utf8))
    exit(2)
}
guard let mascot = Mascot.load(URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write(Data("could not read \(args[1])\n".utf8))
    exit(1)
}

let outDir = URL(fileURLWithPath: args[2]).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// A rounded plate behind the character. Without it the icon is a small animal
/// floating in nothing, which reads as a missing image at Dock size.
func plate(_ side: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    let inset = CGFloat(side) * 0.06
    let rect = NSRect(x: inset, y: inset, width: CGFloat(side) - 2 * inset, height: CGFloat(side) - 2 * inset)
    let path = NSBezierPath(roundedRect: rect,
                            xRadius: CGFloat(side) * 0.22, yRadius: CGFloat(side) * 0.22)
    NSGradient(starting: NSColor(srgbRed: 0.99, green: 0.97, blue: 0.93, alpha: 1),
               ending: NSColor(srgbRed: 0.93, green: 0.89, blue: 0.82, alpha: 1))?
        .draw(in: path, angle: -90)
    let scale = floor(CGFloat(side) * 0.78 / CGFloat(mascot.height))
    if scale >= 1,
       let wity = mascot.image(figure: mascot.defaultFigure, gauge: 2, eyes: "open", frame: 1,
                             skin: mascot.defaultSkin, tint: "#3fb27f",
                             fitting: scale * CGFloat(mascot.height)) {
        let w = wity.size.width, h = wity.size.height
        NSGraphicsContext.current?.imageInterpolation = .none
        wity.draw(in: NSRect(x: (CGFloat(side) - w) / 2, y: (CGFloat(side) - h) / 2,
                            width: w, height: h))
    }
    image.unlockFocus()
    return image
}

func write(_ image: NSImage, _ name: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: outDir.appendingPathComponent(name))
}

for size in [16, 32, 128, 256, 512] {
    write(plate(size), "icon_\(size)x\(size).png")
    write(plate(size * 2), "icon_\(size)x\(size)@2x.png")
}
print("wrote \(outDir.path)")
