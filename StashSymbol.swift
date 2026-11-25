import AppKit

enum StashSymbol {
    // Shared 24-unit drawing. The cut in the top sheet is a bookmark ribbon.
    static func image(size: CGFloat, appIcon: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let transform = NSAffineTransform()
            transform.scale(by: size / 24)
            transform.concat()
            if appIcon {
                NSColor(srgbRed: 0.13, green: 0.13, blue: 0.16, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 1.3, y: 1.3, width: 21.4, height: 21.4), xRadius: 4.7, yRadius: 4.7).fill()
                let inset = NSAffineTransform()
                inset.translateX(by: 3.6, yBy: 3.6)
                inset.scale(by: 0.7)
                inset.concat()
            }
            func sheet(_ color: NSColor, _ vertices: [(CGFloat, CGFloat)]) {
                (appIcon ? color : .black).setFill()
                let path = NSBezierPath()
                for (i, point) in vertices.enumerated() {
                    let vertex = NSPoint(x: point.0, y: point.1)
                    if i == 0 { path.move(to: vertex) } else { path.line(to: vertex) }
                }
                path.close()
                path.fill()
            }
            sheet(NSColor(srgbRed: 0.67, green: 0.57, blue: 0.98, alpha: 1),
                  [(2,8),(12,3),(22,8),(18,10),(14,8),(14,11.9),(12,13)])
            sheet(NSColor(srgbRed: 0.96, green: 0.64, blue: 0.26, alpha: 1),
                  [(2,11),(12,16),(22,11),(22,14),(12,19),(2,14)])
            sheet(NSColor(srgbRed: 0.43, green: 0.81, blue: 0.70, alpha: 1),
                  [(2,16),(12,21),(22,16),(22,18),(12,23),(2,18)])
            return true
        }
        image.isTemplate = !appIcon
        image.accessibilityDescription = "Reading Stash"
        return image
    }
}
