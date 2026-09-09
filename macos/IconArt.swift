import Cocoa

enum BullIcon {
    static func menuImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 2.2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 2, y: 4))
            path.line(to: NSPoint(x: 6.5, y: 9))
            path.line(to: NSPoint(x: 10, y: 6.5))
            path.line(to: NSPoint(x: 16, y: 14))
            path.stroke()
            let head = NSBezierPath()
            head.lineWidth = 2.2
            head.lineCapStyle = .round
            head.lineJoinStyle = .round
            head.move(to: NSPoint(x: 10.5, y: 14))
            head.line(to: NSPoint(x: 16, y: 14))
            head.line(to: NSPoint(x: 16, y: 8.5))
            head.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "상승 그래프 · 주식 검색"
        return image
    }

    static func appImage(size: Int) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let scale = NSAffineTransform()
        scale.scale(by: CGFloat(size) / 1024)
        scale.concat()
        let tile = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 208, yRadius: 208)
        NSGradient(starting: NSColor(srgbRed: 0.045, green: 0.11, blue: 0.085, alpha: 1),
                   ending: NSColor(srgbRed: 0.10, green: 0.24, blue: 0.16, alpha: 1))!.draw(in: tile, angle: 70)
        NSColor(srgbRed: 0.25, green: 0.52, blue: 0.34, alpha: 0.3).setStroke()
        tile.lineWidth = 3
        tile.stroke()
        // Three quiet rising columns keep the silhouette readable at small sizes.
        for (x, height) in [(238.0, 134.0), (426.0, 236.0), (614.0, 348.0)] {
            let bar = NSBezierPath(roundedRect: NSRect(x: x, y: 242, width: 126, height: height), xRadius: 26, yRadius: 26)
            NSGradient(starting: NSColor(srgbRed: 0.15, green: 0.40, blue: 0.25, alpha: 1),
                       ending: NSColor(srgbRed: 0.28, green: 0.64, blue: 0.37, alpha: 1))!.draw(in: bar, angle: 90)
        }
        NSColor(srgbRed: 0.69, green: 0.98, blue: 0.45, alpha: 1).setStroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = 62
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(x: 244, y: 468))
        arrow.line(to: NSPoint(x: 428, y: 645))
        arrow.line(to: NSPoint(x: 537, y: 558))
        arrow.line(to: NSPoint(x: 779, y: 785))
        arrow.stroke()
        let head = NSBezierPath()
        head.lineWidth = 62
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.move(to: NSPoint(x: 599, y: 785))
        head.line(to: NSPoint(x: 779, y: 785))
        head.line(to: NSPoint(x: 779, y: 605))
        head.stroke()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
