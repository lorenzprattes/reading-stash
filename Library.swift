import Foundation
import Darwin

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct CaptureInput {
    let url: URL
    var title: String? = nil
}

struct Entry: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let source: URL
    var saved: Date
    var read: Bool
    var isDocument: Bool { source.isFileURL }

    func matches(_ query: String) -> Bool {
        let haystack = title + " " + (isDocument ? source.lastPathComponent : source.absoluteString)
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { haystack.localizedStandardContains(String($0)) }
    }
}

struct Library {
    let directory: URL
    private let fm = FileManager.default
    private var index: URL { directory.appendingPathComponent("library-v1.json") }

    static let extensions: Set<String> = ["pdf", "txt", "md", "epub", "rtf", "docx", "pages"]
    static func validate(_ url: URL) throws {
        if url.isFileURL {
            guard extensions.contains(url.pathExtension.lowercased()) else {
                throw Failure("Choose a PDF, EPUB, text, Markdown, RTF, Pages, or Word (.docx) document.")
            }
        } else {
            guard ["http", "https"].contains(url.scheme?.lowercased()), !(url.host ?? "").isEmpty,
                  url.user == nil, url.password == nil else { throw Failure("Choose an http or https web address without embedded login details.") }
        }
    }

    func load() throws -> [Entry] {
        do { return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: index)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
    }

    func destination(_ entry: Entry) -> URL {
        entry.isDocument ? directory.appendingPathComponent("Documents").appendingPathComponent(entry.id.uuidString).appendingPathComponent(entry.source.lastPathComponent) : entry.source
    }

    private func change(_ edit: (inout [Entry], inout [URL]) throws -> Void) throws -> [Entry] {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { throw Failure("Cannot open the library lock.") }
        defer { close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw Failure("Cannot lock the library for saving.") }
        var entries = try load()
        var created: [URL] = []
        do {
            try edit(&entries, &created)
            try JSONEncoder().encode(entries).write(to: index, options: .atomic)
            return entries
        } catch {
            for url in created { try? fm.removeItem(at: url) }
            throw error
        }
    }

    func save(_ inputs: [CaptureInput]) throws -> [Entry] {
        guard !inputs.isEmpty else { throw Failure("Choose a link or document to save.") }
        return try change { entries, created in
            let now = Date()
            for input in inputs.reversed() {
                let url = input.url
                try Self.validate(url)
                let name = input.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                if !url.isFileURL, let i = entries.firstIndex(where: { $0.source == url }) {
                    var entry = entries.remove(at: i)
                    entry.saved = now
                    entry.read = false
                    if let name, !name.isEmpty { entry.title = name }
                    entries.insert(entry, at: 0)
                    continue
                }
                let fallback = url.isFileURL ? url.lastPathComponent : (url.host ?? "") + url.path
                let entry = Entry(id: UUID(), title: name?.isEmpty == false ? name! : fallback, source: url, saved: now, read: false)
                if url.isFileURL {
                    let source = url.resolvingSymlinksInPath()
                    guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw Failure("Choose a single document file.") }
                    let target = destination(entry)
                    let folder = target.deletingLastPathComponent()
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    created.append(folder)
                    try fm.copyItem(at: source, to: target)
                }
                entries.insert(entry, at: 0)
            }
        }
    }

    func mark(_ id: UUID, read: Bool) throws -> [Entry] {
        try change { entries, _ in
            guard let i = entries.firstIndex(where: { $0.id == id }) else { throw Failure("This item is no longer in the stash.") }
            entries[i].read = read
        }
    }
}
