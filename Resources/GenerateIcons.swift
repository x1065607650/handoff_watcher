import AppKit
@main struct GenerateIcons {
    static func main() throws {
        let destination = CommandLine.arguments[1]
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        var chunks = Data()
        let types = [16: ["icp4", "ic11"], 32: ["icp5", "ic12"], 128: ["ic07", "ic13"], 256: ["ic08", "ic14"], 512: ["ic09", "ic10"]]
        func word(_ value: Int) -> Data {
            var big = UInt32(value).bigEndian
            return withUnsafeBytes(of: &big) { Data($0) }
        }
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = base * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                Artwork.appIcon(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                NSGraphicsContext.restoreGraphicsState()
                let suffix = scale == 2 ? "@2x" : ""
                let png = bitmap.representation(using: .png, properties: [:])!
                chunks.append(Data(types[base]![scale - 1].utf8))
                chunks.append(word(png.count + 8))
                chunks.append(png)
                try png.write(to: URL(fileURLWithPath: "\(destination)/icon_\(base)x\(base)\(suffix).png"))
            }
        }
        var icns = Data("icns".utf8)
        icns.append(word(chunks.count + 8))
        icns.append(chunks)
        try icns.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
