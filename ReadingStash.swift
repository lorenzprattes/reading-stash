import SwiftUI
import AppKit
import UniformTypeIdentifiers

private typealias LocalState<Value> = SwiftUI.State<Value>
enum Shelf: String, CaseIterable { case unread = "Unread", read = "Read", all = "All" }

final class StashModel: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var shelf = Shelf.unread
    @Published var query = ""
    @Published var notice = ""
    @Published var error: String?
    @Published var findRequest = 0
    private let queue = DispatchQueue(label: "local.readingstash.library", qos: .userInitiated)
    private let library: Library
    var feedback: (Bool) -> Void = { _ in }

    init() {
        let standard = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Reading Stash")
        let override = ProcessInfo.processInfo.environment["READING_STASH_DATA_DIR"]
        library = Library(directory: override.map { URL(fileURLWithPath: $0) } ?? standard)
    }

    private func change(_ work: @escaping (Library) throws -> [Entry], done: @escaping () -> Void = {}, failed: @escaping () -> Void = {}) {
        queue.async { [self] in
            do {
                let updated = try work(library)
                DispatchQueue.main.async { self.entries = updated; done() }
            } catch { DispatchQueue.main.async { self.report(error); failed() } }
        }
    }
    func refresh() { change { try $0.load() } }
    func report(_ problem: Error) { captureLog.notice("Error: domain=\((problem as NSError).domain, privacy: .public) code=\((problem as NSError).code)"); notice = ""; error = problem.localizedDescription; feedback(false) }
    @discardableResult func save(_ inputs: [CaptureInput]) -> Bool {
        save(inputs, completed: nil)
    }
    @discardableResult func save(_ inputs: [CaptureInput], completed: ((Bool) -> Void)?) -> Bool {
        notice = "Saving…"
        captureLog.notice("Save queued: count=\(inputs.count)")
        change({ try $0.save(inputs) }) {
            self.query = ""
            self.shelf = .unread
            self.notice = inputs.count == 1 ? "Saved to Unread" : "Saved \(inputs.count) items to Unread"
            captureLog.notice("Save committed: count=\(inputs.count)")
            self.feedback(true)
            completed?(true)
        } failed: { completed?(false) }
        return true
    }
    func paste() {
        do { save(try PasteCapture.decode(.general)) } catch { report(error) }
    }
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Library.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.prompt = "Save to Stash"
        if panel.runModal() == .OK { save(panel.urls.map { CaptureInput(url: $0) }) }
    }
    func toggle(_ entry: Entry) {
        change({ try $0.mark(entry.id, read: !entry.read) }, done: { self.notice = entry.read ? "Moved to Unread" : "Moved to Read" })
    }
    func open(_ entry: Entry) {
        let url = library.destination(entry)
        do {
            try Library.validate(url)
            if url.isFileURL && !FileManager.default.fileExists(atPath: url.path) { throw Failure("The saved copy is missing from the library.") }
            guard NSWorkspace.shared.open(url) else { throw Failure("macOS could not open this item.") }
        } catch { report(error) }
    }
}

struct DropZone: NSViewRepresentable {
    let model: StashModel
    @Binding var targeted: Bool
    func makeNSView(context: Context) -> DropSurface {
        let view = DropSurface()
        view.accept = model.save
        view.hover = { targeted = $0 }
        view.reject = model.report
        return view
    }
    func updateNSView(_ view: DropSurface, context: Context) {}
}

struct CollectionView: View {
    @Environment(\.colorScheme) private var scheme
    private var accent: Color {
        scheme == .dark ? Color(red: 0.71, green: 0.66, blue: 0.97) : Color(red: 0.38, green: 0.28, blue: 0.66)
    }
    private var canvas: Color { Color(white: scheme == .dark ? 0.105 : 0.985) }
    private var barColor: Color { Color(white: scheme == .dark ? 0.135 : 0.95) }
    private var rule: Color { Color(nsColor: .separatorColor) }
    private var amber: Color { scheme == .dark ? .orange : Color(red: 0.67, green: 0.34, blue: 0.06) }
    private var mint: Color { scheme == .dark ? .mint : Color(red: 0.07, green: 0.45, blue: 0.38) }

    @ObservedObject var model: StashModel
    @LocalState private var targeted = false
    @FocusState private var searchFocus: Bool
    var visible: [Entry] {
        model.entries.filter { (model.shelf == .all || $0.read == (model.shelf == .read)) && $0.matches(model.query) }
    }
    var body: some View {
        let rows = visible
        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                ForEach(Shelf.allCases, id: \.self) { shelf in
                    Button { model.shelf = shelf } label: {
                        Text(shelf.rawValue)
                            .font(.system(size: 13, weight: model.shelf == shelf ? .semibold : .regular))
                            .foregroundStyle(model.shelf == shelf ? Color.primary : .secondary)
                            .frame(height: 40)
                            .overlay(alignment: .bottom) {
                                if model.shelf == shelf { Rectangle().fill(accent).frame(height: 2) }
                            }
                    }.accessibilityAddTraits(model.shelf == shelf ? .isSelected : [])
                }
                Spacer()
                Button(action: model.paste) { Image(systemName: "clipboard").frame(width: 24, height: 28) }
                    .help("Save clipboard (⇧⌘V)").accessibilityLabel("Save clipboard")
                Button(action: model.chooseFiles) { Image(systemName: "plus").frame(width: 24, height: 28) }
                    .help("Add files (⌘O)").accessibilityLabel("Add files")
            }.padding(.horizontal, 18).background(barColor)
            rule.frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search this shelf", text: $model.query).textFieldStyle(.plain).focused($searchFocus)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark") }.accessibilityLabel("Clear search")
                }
            }.padding(.horizontal, 18).frame(height: 36)
            rule.frame(height: 1)
            if rows.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: model.query.isEmpty ? "tray" : "magnifyingglass")
                        .font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
                    Text(model.query.isEmpty ? (model.shelf == .read ? "No finished items" : "Nothing on this shelf yet") : "No matching items")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    if !model.query.isEmpty { Button("Clear search") { model.query = "" }.foregroundStyle(accent) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { entry in
                            HStack(spacing: 12) {
                                let pdf = entry.isDocument && entry.source.pathExtension.lowercased() == "pdf"
                                Image(systemName: entry.isDocument ? (pdf ? "doc.richtext.fill" : "doc.fill") : "link")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(entry.isDocument ? (pdf ? amber : mint) : accent)
                                    .frame(width: 22).accessibilityLabel(entry.isDocument ? "Document" : "Link")
                                Button { model.open(entry) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                                        Text(entry.isDocument ? entry.source.pathExtension.uppercased() : entry.source.absoluteString)
                                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.help("Open \(entry.title)")
                                Text(entry.saved.formatted(.dateTime.month(.abbreviated).day().year()))
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                Button { model.toggle(entry) } label: {
                                    Image(systemName: entry.read ? "checkmark.square.fill" : "square").frame(width: 22, height: 28)
                                }.help(entry.read ? "Move to Unread" : "Mark as read")
                                    .accessibilityLabel(entry.read ? "Move to Unread" : "Mark as read")
                            }.padding(.horizontal, 18).padding(.vertical, 10)
                            rule.frame(height: 1)
                        }
                    }
                }
            }
            rule.frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                Text(targeted ? "Release to save" : "Drop link or file")
                Spacer()
                Text(model.notice.isEmpty ? "\(rows.count) · Newest first" : model.notice).lineLimit(1)
            }.font(.system(size: 11, design: .monospaced)).foregroundStyle(targeted ? accent : Color.secondary)
                .padding(.horizontal, 16).frame(height: 32).background(targeted ? accent.opacity(0.16) : barColor)
                .overlay(DropZone(model: model, targeted: $targeted))
        }
        .buttonStyle(.plain).background(canvas).tint(accent)
        .onChange(of: model.findRequest) { searchFocus = true }
        .alert("Reading Stash", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

#if !STASH_UI_CHECK
@main
#endif
final class App: NSObject, NSApplicationDelegate {
    let model = StashModel()
    var window: NSWindow!
    var tray: NSStatusItem!
    var dropPanel: NSPanel!
    var target: FloatingTarget!
    var targetMenuItem: NSMenuItem!
    private var cornerTimer: Timer?
    private var dwellStart: TimeInterval?
    private var cornerLatched = false
    private var pressOrigin: NSPoint?
    private var lastShown: TimeInterval = 0
    private var cornerSavePending = false
    private var receiptUntil: TimeInterval = 0
    var reset: DispatchWorkItem?

    static func main() {
        let app = NSApplication.shared
        let owner = App()
        app.delegate = owner
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(owner) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu()
        func submenu(_ name: String) -> NSMenu {
            let item = main.addItem(withTitle: name, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: name)
            item.submenu = menu
            return menu
        }
        let app = submenu("Reading Stash")
        app.addItem(withTitle: "Show Reading Stash", action: #selector(show), keyEquivalent: "0").target = self
        app.addItem(withTitle: "Quit Reading Stash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        targetMenuItem = app.insertItem(withTitle: "Lower-Right Corner", action: #selector(toggleTarget), keyEquivalent: "", at: 1)
        targetMenuItem.target = self
        let file = submenu("File")
        file.addItem(withTitle: "Add Files…", action: #selector(addFiles), keyEquivalent: "o").target = self
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = submenu("Edit")
        for (title, key, selector) in [("Undo","z","undo:"),("Cut","x","cut:"),("Copy","c","copy:"),("Paste","v","paste:"),("Select All","a","selectAll:")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        let paste = edit.addItem(withTitle: "Save Clipboard to Stash", action: #selector(saveClipboard), keyEquivalent: "v")
        paste.target = self
        paste.keyEquivalentModifierMask = [.command,.shift]
        edit.addItem(withTitle: "Find", action: #selector(find), keyEquivalent: "f").target = self
        NSApp.mainMenu = main
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 570), styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "Reading Stash"
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.minSize = NSSize(width: 580, height: 410)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CollectionView(model: model))
        window.center()
        window.setFrameAutosaveName("Reading Stash")
        tray = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = tray.button {
            icon()
            button.toolTip = "Reading Stash · Click to browse, right-click for options"
            button.target = self
            button.action = #selector(statusClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let surface = DropSurface(frame: button.bounds)
            surface.autoresizingMask = [.width,.height]
            surface.accept = model.save
            surface.reject = model.report
            surface.hover = { button.highlight($0) }
            button.addSubview(surface)
        }
        createCornerTarget()
        model.feedback = { [weak self] success in
            self?.reset?.cancel()
            self?.icon(success ? "checkmark.circle.fill" : "exclamationmark.triangle")
            if !success { self?.show() }
            let task = DispatchWorkItem { [weak self] in self?.icon() }
            self?.reset = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: task)
        }
        model.refresh()
    }
    private func createCornerTarget() {
        let screen = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)?.visibleFrame ?? window.frame
        let frame = Self.cornerFrame(in: screen)
        dropPanel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        dropPanel.title = "Reading Stash drop target"
        dropPanel.level = .floating
        dropPanel.isOpaque = false
        dropPanel.backgroundColor = .clear
        dropPanel.hasShadow = true
        dropPanel.hidesOnDeactivate = false
        dropPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        target = FloatingTarget(frame: NSRect(origin: .zero, size: frame.size))
        target.accept = { [weak self] inputs in
            guard let self else { return false }
            self.cornerSavePending = true
            self.target.caption = "Saving…"
            return self.model.save(inputs) { success in
                self.cornerSavePending = false
                if self.targetMenuItem.state == .on {
                    self.showReceipt(success ? "Saved ✓" : "Save failed", at: ProcessInfo.processInfo.systemUptime)
                }
            }
        }
        target.unsupported = { [weak self] in self?.target.caption = "Drag address instead" }
        target.reject = model.report
        dropPanel.contentView = target
        startCornerTracking()
    }

    static func cornerFrame(in screen: NSRect) -> NSRect {
        NSRect(x: screen.maxX - 168, y: screen.minY + 16, width: 152, height: 38)
    }

    private func startCornerTracking() {
        targetMenuItem.state = .on
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            let held = NSEvent.pressedMouseButtons & 1 != 0
            let point = NSEvent.mouseLocation
            let display = NSScreen.screens.first { $0.frame.contains(point) }
            let now = ProcessInfo.processInfo.systemUptime
            self.trackOverview(point: point, buttonsDown: NSEvent.pressedMouseButtons != 0, display: display?.frame, now: now)
            self.trackCorner(point: point, held: held, screen: display?.visibleFrame, now: now)
        }
        timer.tolerance = 0.015
        RunLoop.main.add(timer, forMode: .common)
        cornerTimer = timer
    }

    // Use physical display bounds for the hover gesture. The drop panel uses the area above the Dock.
    func trackOverview(point: NSPoint, buttonsDown: Bool, display: NSRect?, now: TimeInterval) {
        guard let display, NSRect(x: display.maxX - 12, y: display.minY, width: 12, height: 12).contains(point) else {
            dwellStart = nil
            cornerLatched = false
            return
        }
        if buttonsDown || pressOrigin != nil || cornerSavePending || dropPanel.isVisible {
            dwellStart = nil
            cornerLatched = true
            return
        }
        guard !cornerLatched else { return }
        guard let start = dwellStart else { dwellStart = now; return }
        if now - start >= 0.45 {
            cornerLatched = true
            show()
        }
    }

    func trackCorner(point: NSPoint, held: Bool, screen: NSRect?, now: TimeInterval) {
        let released = !held && pressOrigin != nil
        if !held { pressOrigin = nil }
        if cornerSavePending { return }
        if receiptUntil > 0 {
            if now < receiptUntil && !held { return }
            receiptUntil = 0
            dropPanel.ignoresMouseEvents = false
            dropPanel.orderOut(nil)
        }
        if held, pressOrigin == nil { pressOrigin = point }
        if let origin = pressOrigin, let screen, hypot(point.x - origin.x, point.y - origin.y) >= 4 {
            let frame = Self.cornerFrame(in: screen)
            if frame.insetBy(dx: -72, dy: -64).contains(point) {
                if dropPanel.frame != frame { dropPanel.setFrame(frame, display: true) }
                if !dropPanel.isVisible {
                    let board = NSPasteboard(name: .drag)
                    let formats = board.types ?? []
                    let privateTab = formats.contains(PasteCapture.firefoxWildcard) && !formats.contains(where: PasteCapture.types.contains)
                    target.caption = privateTab ? "Drag address instead" : "Drop to Stash"
                    captureLog.notice("Corner shown: drag formats=\(describeFormats(board), privacy: .public)")
                    dropPanel.orderFrontRegardless()
                }
                lastShown = now
                return
            }
        }
        if released, dropPanel.isVisible, dropPanel.frame.contains(point) {
            // Defer the missed-drop verdict until AppKit has had time to deliver performDragOperation.
            let attempt = lastShown
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                guard let self, self.lastShown == attempt, self.receiptUntil == 0, !self.cornerSavePending,
                      self.targetMenuItem.state == .on else { return }
                let board = NSPasteboard(name: .drag)
                captureLog.notice("Released over corner without delivered drop: formats=\(describeFormats(board), privacy: .public)")
                self.model.notice = "Nothing saved. Drag the address-bar icon, a page link, or a Finder file."
                self.showReceipt("Nothing saved", at: ProcessInfo.processInfo.systemUptime)
            }
        }
        // Give AppKit time to deliver the final drop after the button comes up.
        if dropPanel.isVisible, now - lastShown > 0.25 { dropPanel.orderOut(nil) }
    }

    private func showReceipt(_ message: String, at now: TimeInterval) {
        target.hover(false)
        target.caption = message
        receiptUntil = now + 1.6
        dropPanel.ignoresMouseEvents = true
        dropPanel.orderFrontRegardless()
    }

    @objc func toggleTarget() {
        if let timer = cornerTimer {
            timer.invalidate()
            dwellStart = nil
            cornerLatched = false
            cornerTimer = nil
            pressOrigin = nil
            dropPanel.orderOut(nil)
            targetMenuItem.state = .off
        } else { startCornerTracking() }
    }
    @objc func statusClick(_ button: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Reading Stash", action: #selector(show), keyEquivalent: "").target = self
            let corner = menu.addItem(withTitle: "Lower-Right Corner", action: #selector(toggleTarget), keyEquivalent: "")
            corner.target = self
            corner.state = targetMenuItem.state
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Reading Stash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "").target = NSApp
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 2), in: button)
        } else { show() }
    }
    func icon(_ symbol: String? = nil) {
        let image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: "Reading Stash") }
            ?? StashSymbol.image(size: 18, appIcon: false)
        image.isTemplate = true
        tray.button?.image = image
    }
    @objc func show() { if window.isMiniaturized { window.deminiaturize(nil) }; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func addFiles() { show(); model.chooseFiles() }
    @objc func saveClipboard() { model.paste() }
    @objc func find() { show(); model.findRequest += 1 }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
