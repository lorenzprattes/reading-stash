import AppKit

@main enum Checks {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = Library(directory: root.appendingPathComponent("stash"))
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func check(_ condition: @autoclosure () throws -> Bool, _ failure: String) throws {
            if try !condition() { throw Failure(failure) }
        }
        let url = URL(string: "https://example.org/reading")!
        let file = root.appendingPathComponent("Sample.pdf")
        let data = Data("test document".utf8)
        try data.write(to: file)
        let web = CaptureInput(url: url, title: "Café society")
        let fileInput = CaptureInput(url: file)
        let webEntry = try library.save([web])[0]
        let fileEntry = try library.save([fileInput])[0]
        try fm.moveItem(at: file, to: root.appendingPathComponent("Moved.pdf"))
        try check(try Data(contentsOf: library.destination(fileEntry)) == data, "Lost file after move")
        try check(try library.load().map(\.id) == [fileEntry.id, webEntry.id], "Incorrect order after restart")
        try check(webEntry.matches("society cafe") && webEntry.matches("EXAMPLE.org") && fileEntry.matches(".pdf"), "Search missed metadata")
        _ = try library.mark(webEntry.id, read: true)
        let resaved = try library.save([CaptureInput(url: url)])
        try check(resaved.count == 2 && resaved[0].id == webEntry.id && resaved[0].title == webEntry.title && !resaved[0].read, "Repeated URL lost title, order, or identity")
        let otherFile = CaptureInput(url: root.appendingPathComponent("Moved.pdf"))
        do { _ = try library.save([fileInput, otherFile]); throw Failure("Accepted missing PDF") } catch is CocoaError {}
        try check(try library.load() == resaved, "Failed batch modified index")
        let folders = try fm.contentsOfDirectory(atPath: library.directory.appendingPathComponent("Documents").path)
        try check(folders == [fileEntry.id.uuidString], "Failed batch left a copy")
        let index = library.directory.appendingPathComponent("library-v1.json")
        let damaged = Data("invalid".utf8)
        try damaged.write(to: index)
        do { _ = try library.save([web]); throw Failure("Overwrote damaged library") } catch is DecodingError {}
        try check(try Data(contentsOf: index) == damaged, "Damaged index changed")
        print("Library checks passed")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try check(DropSurface.operation(formats: [PasteCapture.firefoxWildcard], mask: .every).isEmpty, "Private Firefox marker accepted without URL")
        try check(DropSurface.operation(formats: [.URL], mask: .link) == .link, "Link-only drag rejected")
        try check(DropSurface.operation(formats: [.fileURL], mask: .move).isEmpty, "Move-only drag accepted")
        let firefox = NSPasteboardItem()
        firefox.setString(url.absoluteString + "\nFirefox page", forType: PasteCapture.moz)
        let chrome = NSPasteboardItem()
        chrome.setString("https://example.org/chrome", forType: .URL)
        chrome.setString("Chrome page", forType: PasteCapture.urlName)
        let finder = NSPasteboardItem()
        finder.setString(file.absoluteString, forType: .fileURL)
        try check(board.writeObjects([firefox, chrome, finder]), "Cannot initialize test pasteboard")
        let mixed = try PasteCapture.decode(board)
        try check(mixed.map(\.title) == ["Firefox page", "Chrome page", nil] && mixed.last?.url == file, "Mixed pasteboard lost items or titles")
        board.clearContents()
        board.setString("https://example.org/a\nhttps://example.org/b", forType: .string)
        try check(try PasteCapture.decode(board).count == 2, "Multiline paste lost a link")
        board.clearContents()
        board.setPropertyList([[url.absoluteString],["Named page"]], forType: PasteCapture.named)
        try check(try PasteCapture.decode(board).first?.title == "Named page", "Lost named URL")
        print("Synthetic browser, Finder, and clipboard checks passed")
    }
}
