import AppKit

@MainActor
final class MenuIconView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setStroke()
        let rear = NSBezierPath()
        rear.move(to: NSPoint(x: 3.5, y: 11.75))
        rear.line(to: NSPoint(x: 3, y: 11.75))
        rear.curve(to: NSPoint(x: 1, y: 9.75), controlPoint1: NSPoint(x: 1.9, y: 11.75), controlPoint2: NSPoint(x: 1, y: 10.85))
        rear.line(to: NSPoint(x: 1, y: 3))
        rear.curve(to: NSPoint(x: 3, y: 1), controlPoint1: NSPoint(x: 1, y: 1.9), controlPoint2: NSPoint(x: 1.9, y: 1))
        rear.line(to: NSPoint(x: 11.5, y: 1))
        rear.curve(to: NSPoint(x: 13.5, y: 3), controlPoint1: NSPoint(x: 12.6, y: 1), controlPoint2: NSPoint(x: 13.5, y: 1.9))
        rear.lineWidth = 1.5
        rear.lineCapStyle = .round
        rear.stroke()

        let front = NSBezierPath(roundedRect: NSRect(x: 5.5, y: 5, width: 13.5, height: 12), xRadius: 2, yRadius: 2)
        front.lineWidth = 1.5
        front.stroke()

        let titleBar = NSBezierPath()
        titleBar.move(to: NSPoint(x: 5.75, y: 8.5))
        titleBar.line(to: NSPoint(x: 18.75, y: 8.5))
        titleBar.lineWidth = 1.25
        titleBar.stroke()
    }
}

let view = MenuIconView(frame: NSRect(x: 0, y: 0, width: 20, height: 18))
let output = URL(fileURLWithPath: "Peekaboo/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.pdf")
try view.dataWithPDF(inside: view.bounds).write(to: output)
