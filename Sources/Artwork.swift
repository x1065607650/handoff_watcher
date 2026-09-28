import AppKit

enum HandoffWatcherState { case checking, healthy, unhealthy, restarting }
enum Artwork {
    static func status(_ state: HandoffWatcherState, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.scaleBy(x: size / 18, y: size / 18)
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let body = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 1.5, width: 10, height: 14), xRadius: 1.8, yRadius: 1.8)
            body.lineWidth = 1.35
            body.stroke()
            let clip = NSBezierPath(roundedRect: NSRect(x: 5, y: 13.5, width: 5, height: 3), xRadius: 1, yRadius: 1)
            clip.fill()
            for y in [10.5, 7.5] {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: 5, y: y)); line.line(to: NSPoint(x: 9, y: y))
                line.lineWidth = 1.1; line.lineCapStyle = .round; line.stroke()
            }
            // Knock out the badge backing so the glyph remains clear in either system appearance.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 8, y: 0, width: 10, height: 9)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let mark = NSBezierPath()
            mark.lineWidth = 1.6; mark.lineCapStyle = .round; mark.lineJoinStyle = .round
            switch state {
            case .healthy:
                mark.move(to: NSPoint(x: 9.5, y: 4)); mark.line(to: NSPoint(x: 12, y: 1.8)); mark.line(to: NSPoint(x: 16.5, y: 6.7)); mark.stroke()
            case .unhealthy:
                mark.move(to: NSPoint(x: 10.5, y: 1.8)); mark.line(to: NSPoint(x: 15.5, y: 6.8))
                mark.move(to: NSPoint(x: 10.5, y: 6.8)); mark.line(to: NSPoint(x: 15.5, y: 1.8)); mark.stroke()
            case .checking, .restarting:
                for x in [10.0, 13.0, 16.0] { NSBezierPath(ovalIn: NSRect(x: x - 0.7, y: 3, width: 1.4, height: 1.4)).fill() }
            }
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        return image
    }
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.scaleBy(x: size / 1024, y: size / 1024)
            let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
            NSColor(calibratedRed: 0.13, green: 0.40, blue: 0.78, alpha: 1).setFill(); tile.fill()
            NSShadow().set()
            NSGradient(starting: NSColor(calibratedRed: 0.27, green: 0.70, blue: 0.94, alpha: 1), ending: NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.75, alpha: 1))!.draw(in: tile, angle: -75)
            let board = NSBezierPath(roundedRect: NSRect(x: 302, y: 238, width: 420, height: 522), xRadius: 58, yRadius: 58)
            NSColor.white.withAlphaComponent(0.96).setStroke(); board.lineWidth = 34; board.stroke()
            let clip = NSBezierPath(roundedRect: NSRect(x: 417, y: 716, width: 190, height: 88), xRadius: 30, yRadius: 30)
            NSColor.white.setFill(); clip.fill()
            for (y, right) in [(620.0, 625.0), (535.0, 573.0)] {
                let line = NSBezierPath(); line.move(to: NSPoint(x: 398, y: y)); line.line(to: NSPoint(x: right, y: y)); line.lineWidth = 30; line.lineCapStyle = .round; line.stroke()
            }
            let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 399, y: 392)); arrow.line(to: NSPoint(x: 625, y: 392)); arrow.move(to: NSPoint(x: 561, y: 453)); arrow.line(to: NSPoint(x: 625, y: 392)); arrow.line(to: NSPoint(x: 561, y: 331)); arrow.lineWidth = 32; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }
}
