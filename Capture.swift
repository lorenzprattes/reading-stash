import AppKit
import UniformTypeIdentifiers
import OSLog

let captureLog = Logger(subsystem: "local.experiments.reading-stash", category: "capture")

func describeFormats(_ board: NSPasteboard) -> String {
    (board.types ?? []).map(\.rawValue).joined(separator: ",")
}

enum PasteCapture {
    static let firefoxWildcard = NSPasteboard.PasteboardType("org.mozilla.MozillaWildcard")
    static let moz = NSPasteboard.PasteboardType("org.mozilla.url")
    static let mozText = mimeType("text/x-moz-url")
    static let named = NSPasteboard.PasteboardType(
        UTType(tag: "WebURLsWithTitlesPboardType", tagClass: UTTagClass(rawValue: "com.apple.nspboard-type"), conformingTo: nil)!.identifier
    )
    private static func mimeType(_ name: String) -> NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(UTType(tag: name, tagClass: .mimeType, conformingTo: nil)!.identifier)
    }
    static let uriList = mimeType("text/uri-list")
    static let urlName = NSPasteboard.PasteboardType("public.url-name")
    static let types: [NSPasteboard.PasteboardType] = [.fileURL, named, moz, mozText, .URL, uriList, .string]

    static func decode(_ board: NSPasteboard) throws -> [CaptureInput] {
        func parse(_ string: String, _ title: String? = nil) throws -> CaptureInput {
            let raw = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.contains(where: \.isWhitespace), let url = URL(string: raw) else { throw Failure("Copy or drag a complete web address.") }
            try Library.validate(url)
            return CaptureInput(url: url, title: title)
        }
        var inputs: [CaptureInput] = []
        for item in board.pasteboardItems ?? [] {
            if let raw = item.string(forType: .fileURL) {
                inputs.append(try parse(raw))
            } else if let pairs = item.propertyList(forType: named) as? [[String]], pairs.count == 2, !pairs[0].isEmpty, pairs[0].count == pairs[1].count {
                for (url, title) in zip(pairs[0], pairs[1]) { inputs.append(try parse(url, title)) }
            } else if let raw = item.string(forType: moz) ?? item.string(forType: mozText) {
                let lines = raw.split(whereSeparator: \.isNewline).map(String.init)
                inputs.append(try parse(lines.first ?? "", lines.dropFirst().first))
            } else if let raw = item.string(forType: .URL) {
                inputs.append(try parse(raw, item.string(forType: urlName)))
            } else if let raw = item.string(forType: uriList) ?? item.string(forType: .string) {
                for line in raw.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
                    inputs.append(try parse(String(line)))
                }
            } else { throw Failure("Drag the address-bar icon or a Finder document.") }
        }
        guard !inputs.isEmpty else { throw Failure("Copy a web address or a Finder document first.") }
        return inputs
    }
}

// Use the same native drag destination on the menu-bar button and the window's drop zone.
class DropSurface: NSView {
    var passesClicksThrough = true
    var accept: ([CaptureInput]) -> Bool = { _ in false }
    var hover: (Bool) -> Void = { _ in }
    var reject: (Error) -> Void = { _ in }
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes(PasteCapture.types) }
    required init?(coder: NSCoder) { fatalError("Unused initializer") }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if passesClicksThrough, let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp].contains(event.type) { return nil }
        return super.hitTest(point)
    }
    var unsupported: () -> Void = {}
    static func operation(formats: [NSPasteboard.PasteboardType], mask: NSDragOperation) -> NSDragOperation {
        guard formats.contains(where: PasteCapture.types.contains) else { return [] }
        if mask.contains(.copy) { return .copy }
        if mask.contains(.link) { return .link }
        return []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let board = sender.draggingPasteboard
        let operation = Self.operation(formats: board.types ?? [], mask: sender.draggingSourceOperationMask)
        captureLog.notice("Entered target: formats=\(describeFormats(board), privacy: .public) mask=\(sender.draggingSourceOperationMask.rawValue) selected=\(operation.rawValue)")
        hover(!operation.isEmpty)
        if operation.isEmpty { unsupported() }
        return operation
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hover(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hover(false)
        return receive(sender.draggingPasteboard)
    }
    func receive(_ board: NSPasteboard) -> Bool {
        do {
            let inputs = try PasteCapture.decode(board)
            captureLog.notice("Drop delivered: count=\(inputs.count) formats=\(describeFormats(board), privacy: .public)")
            return accept(inputs)
        } catch {
            captureLog.notice("Drop rejected by decoder: formats=\(describeFormats(board), privacy: .public)")
            reject(error)
            return false
        }
    }
}

final class FloatingTarget: DropSurface {
    var caption = "Drop to Stash" { didSet { needsDisplay = true } }
    private var highlighted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        passesClicksThrough = false
        registerForDraggedTypes(PasteCapture.types + [PasteCapture.firefoxWildcard])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Reading Stash drop target")
        hover = { [weak self] active in
            self?.highlighted = active
            self?.needsDisplay = true
        }
    }
    required init?(coder: NSCoder) { fatalError("Unused initializer") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        (highlighted ? NSColor.selectedContentBackgroundColor : .windowBackgroundColor).setFill()
        shape.fill()
        NSColor.systemPurple.setFill()
        NSBezierPath(rect: NSRect(x: 1, y: 1, width: 3, height: bounds.height - 2)).fill()
        let text = (highlighted ? "Release to save" : caption) as NSString
        let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: highlighted ? NSColor.alternateSelectedControlTextColor : .labelColor]
        let size = text.size(withAttributes: style)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: style)
    }
}
