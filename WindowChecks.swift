import AppKit

// Optional desktop gesture check. Source and destination belong to the test process.
final class LinkSource: NSView, NSDraggingSource {
    var began = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        guard !began else { return }
        began = true
        let url = NSURL(string: "https://example.org/desktop-gesture")!
        let item = NSDraggingItem(pasteboardWriter: url)
        item.setDraggingFrame(bounds, contents: NSImage(systemSymbolName: "link", accessibilityDescription: nil))
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

func driveDrag(to panel: NSPanel) throws {
    guard CGPreflightPostEventAccess() else { throw Failure("Desktop mouse-event permission unavailable.") }
    let destination = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
    let sourceFrame = NSRect(x: destination.x - 215, y: destination.y - 28, width: 70, height: 56)
    let source = NSWindow(contentRect: sourceFrame, styleMask: .borderless, backing: .buffered, defer: false)
    source.level = .floating
    source.contentView = LinkSource(frame: NSRect(origin: .zero, size: sourceFrame.size))
    source.orderFrontRegardless()
    defer { source.orderOut(nil) }
    let screenTop = NSScreen.screens[0].frame.maxY
    let start = CGPoint(x: sourceFrame.midX, y: screenTop - sourceFrame.midY)
    let end = CGPoint(x: destination.x, y: screenTop - destination.y)
    let previous = CGEvent(source: nil)?.location
    defer { if let previous { CGWarpMouseCursorPosition(previous) } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
        func send(_ type: CGEventType, _ t: CGFloat) {
            let point = CGPoint(x: start.x + t * (end.x - start.x), y: start.y + t * (end.y - start.y))
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        send(.mouseMoved, 0)
        send(.leftMouseDown, 0)
        for i in 1...20 {
            Thread.sleep(forTimeInterval: 0.035)
            send(.leftMouseDragged, CGFloat(i) / 20)
        }
        Thread.sleep(forTimeInterval: 0.15)
        send(.leftMouseUp, 1)
    }
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.03), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
}

@main enum WindowChecks {
    static func libraryEntries(_ folder: URL) throws -> [Entry] { try Library(directory: folder).load() }
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        setenv("READING_STASH_DATA_DIR", folder.path, 1)
        let application = NSApplication.shared
        let owner = App()
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        owner.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        guard let window = owner.window, let button = owner.tray?.button,
              let drop = button.subviews.compactMap({ $0 as? DropSurface }).first else { throw Failure("Missing window or menu-bar destination") }
        window.performClose(nil)
        guard !window.isVisible, owner.tray.isVisible else { throw Failure("Closing window hid menu-bar destination") }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.setString("https://example.org/hidden-window", forType: .URL)
        guard drop.receive(pb) else { throw Failure("Menu-bar drop rejected") }
        let deadline = Date().addingTimeInterval(5)
        while owner.model.entries.isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        let entries = try Library(directory: folder).load()
        guard !window.isVisible, entries.first?.source.absoluteString == "https://example.org/hidden-window" else { throw Failure("Hidden-window save failed") }
        guard !owner.dropPanel.isVisible, let screen = NSScreen.main?.visibleFrame else { throw Failure("Target must start hidden") }
        let frame = App.cornerFrame(in: screen)
        let near = NSPoint(x: frame.midX, y: frame.midY)
        owner.trackCorner(point: near, held: false, screen: screen, now: 1)
        guard !owner.dropPanel.isVisible else { throw Failure("Ordinary hover revealed target") }
        owner.trackCorner(point: NSPoint(x: screen.midX, y: screen.midY), held: true, screen: screen, now: 2)
        owner.trackCorner(point: near, held: true, screen: screen, now: 3)
        guard owner.dropPanel.isVisible, owner.dropPanel.frame == frame else { throw Failure("Dragging toward the corner did not reveal target") }
        owner.trackCorner(point: near, held: false, screen: screen, now: 4)
        guard !owner.dropPanel.isVisible else { throw Failure("Canceled drag left target visible") }
        owner.trackCorner(point: NSPoint(x: screen.midX, y: screen.midY), held: true, screen: screen, now: 5)
        owner.trackCorner(point: near, held: true, screen: screen, now: 6)
        pb.clearContents()
        pb.setString("https://example.org/floating-target", forType: .URL)
        guard owner.target.receive(pb) else { throw Failure("Floating capture rejected") }
        let timeout = Date().addingTimeInterval(3)
        while owner.model.entries.count < 2, Date() < timeout { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        guard !window.isVisible, owner.target.caption == "Saved ✓", owner.dropPanel.ignoresMouseEvents, try libraryEntries(folder).first?.source.absoluteString == "https://example.org/floating-target" else { throw Failure("Floating target failed to save in background") }
        owner.toggleTarget()
        owner.toggleTarget()
        guard !owner.dropPanel.isVisible, owner.targetMenuItem.state == .on else { throw Failure("Re-enabling target must leave it hidden") }
        if CommandLine.arguments.contains("--mouse-drag") {
            try driveDrag(to: owner.dropPanel)
            guard !window.isVisible, try libraryEntries(folder).first?.source.absoluteString == "https://example.org/desktop-gesture" else { throw Failure("Desktop drag did not reach floating target") }
            print("Native desktop drag reached floating target with main window closed")
        }
        let now = ProcessInfo.processInfo.systemUptime
        owner.trackCorner(point: NSPoint(x: screen.midX, y: screen.midY), held: true, screen: screen, now: now)
        owner.trackCorner(point: near, held: true, screen: screen, now: now + 0.01)
        owner.trackCorner(point: near, held: false, screen: screen, now: now + 0.02)
        let verdictDeadline = Date().addingTimeInterval(1)
        while owner.target.caption != "Nothing saved", Date() < verdictDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        guard owner.target.caption == "Nothing saved", owner.model.notice.contains("Nothing saved") else { throw Failure("Missed drop lacked visible feedback") }
        // Negative-origin screen, with the physical corner below the visible Dock area.
        let display = NSRect(x: -1280, y: -100, width: 1280, height: 800)
        let corner = NSPoint(x: -1, y: -99)
        func sample(_ time: TimeInterval, down: Bool = false, outside: Bool = false) {
            owner.trackOverview(point: outside ? .zero : corner, buttonsDown: down, display: display, now: time)
        }
        owner.dropPanel.orderOut(nil)
        sample(10, outside: true)
        sample(11)
        sample(11.2)
        guard !window.isVisible else { throw Failure("Brief corner pass opened overview") }
        sample(11.6)
        guard window.isVisible else { throw Failure("Corner dwell did not open overview") }
        window.performClose(nil)
        sample(12.6)
        guard !window.isVisible else { throw Failure("Stationary pointer reopened overview") }
        sample(13, outside: true)
        sample(14, down: true)
        sample(15)
        sample(16)
        guard !window.isVisible else { throw Failure("Drag release opened overview") }
        sample(17, outside: true)
        sample(18)
        sample(19)
        guard window.isVisible else { throw Failure("Corner did not rearm after leaving") }
        window.performClose(nil)
        button.performClick(nil)
        guard window.isVisible, owner.model.entries == (try libraryEntries(folder)) else { throw Failure("Click did not reopen saved collection") }
        print("Idle hover, drag reveal, cancel, closed-window capture, persistence, and reopening passed")
    }
}
