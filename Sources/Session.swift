import AppKit

@objc(MarkdownApplication)
final class MarkdownApplication: NSApplication {
    override func terminate(_ sender: Any?) {
        // NSApplication's document review runs before applicationShouldTerminate.
        // Persist drafts before entering that review, then allow a clean exit.
        if let delegate = delegate as? AppDelegate, !delegate.prepareSessionForQuit() { return }
        super.terminate(sender)
    }
}


struct SessionTab: Codable {
    var id = UUID()
    var path: String?
    var source: String
    var encoding: UInt
    var isEdited: Bool
    var readingState: ReadingState
    var diskBaseline: Data?

    init(document: MarkdownDocument) {
        path = document.fileURL?.path
        source = document.source
        encoding = document.encoding.rawValue
        isEdited = document.isDocumentEdited
        readingState = document.captureReadingState()
        diskBaseline = document.diskBaseline
    }
}

struct SessionSnapshot: Codable {
    var version = 1
    var tabs: [SessionTab]
    var selectedID: UUID?

    static func capture(documents: [MarkdownDocument], windows: [NSWindow], selected: NSWindow?) -> SessionSnapshot {
        var ordered = [MarkdownDocument]()
        var seen = Set<ObjectIdentifier>()
        for window in windows {
            for tab in window.tabbedWindows ?? [window] {
                guard let document = documents.first(where: { $0.windowControllers.contains { $0.window === tab } }),
                      seen.insert(ObjectIdentifier(document)).inserted else { continue }
                ordered.append(document)
            }
        }
        for document in documents where seen.insert(ObjectIdentifier(document)).inserted { ordered.append(document) }
        var tabs = [SessionTab]()
        var selectedID: UUID?
        for document in ordered {
            // The automatic empty startup document is not a useful recovery tab.
            if document.fileURL == nil && document.source.isEmpty && !document.isDocumentEdited { continue }
            let tab = SessionTab(document: document)
            if document.windowControllers.contains(where: { $0.window === selected }) { selectedID = tab.id }
            tabs.append(tab)
        }
        return SessionSnapshot(tabs: tabs, selectedID: selectedID ?? tabs.first?.id)
    }
}

struct SessionStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("session.json") }
    static var live: SessionStore {
        SessionStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MD Mini", isDirectory: true))
    }
    func load() throws -> SessionSnapshot? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: Data(contentsOf: file))
        guard snapshot.version == 1 else {
            throw NSError(domain: "MDMini.Session", code: 1, userInfo: [NSLocalizedDescriptionKey: "Этот сеанс сохранён более новой версией MD Mini."])
        }
        return snapshot
    }
    func save(_ snapshot: SessionSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

enum SessionRestorer {
    @discardableResult
    static func restore(_ snapshot: SessionSnapshot, controller: NSDocumentController = .shared) -> [MarkdownDocument] {
        var restored = [MarkdownDocument]()
        var anchor: NSWindow?
        var selectedWindow: NSWindow?
        // A file opened explicitly by Finder at launch should keep the focus.
        let launchWindow = NSApp.keyWindow
        for tab in snapshot.tabs {
            if let alreadyRestored = controller.documents.compactMap({ $0 as? MarkdownDocument }).first(where: { $0.restoredSessionID == tab.id }) {
                if tab.id == snapshot.selectedID { selectedWindow = alreadyRestored.windowControllers.first?.window }
                continue
            }
            var url = tab.path.map { URL(fileURLWithPath: $0) }
            var isRecoveryCopy = false
            if let fileURL = url, let existing = controller.document(for: fileURL) as? MarkdownDocument {
                if tab.isEdited && !existing.isDocumentEdited {
                    existing.source = tab.source
                    existing.encoding = String.Encoding(rawValue: tab.encoding)
                    existing.diskBaseline = tab.diskBaseline
                    existing.lastNoticedFingerprint = tab.diskBaseline
                    existing.readingState = tab.readingState
                    existing.restoringPosition = true
                    if existing.editor != nil {
                        existing.editor.string = tab.source
                        existing.modes.selectedSegment = tab.readingState.mode
                        existing.changeMode()
                    } else {
                        existing.restoredReadingState = tab.readingState
                        existing.makeWindowControllers()
                        existing.showWindows()
                    }
                    existing.updateChangeCount(.changeDone)
                    existing.checkDisk()
                } else if tab.isEdited && existing.isDocumentEdited {
                    // Keep both drafts if a document is already being edited at launch.
                    url = nil
                    isRecoveryCopy = true
                }
                if !isRecoveryCopy {
                    existing.restoredSessionID = tab.id
                    if tab.id == snapshot.selectedID { selectedWindow = existing.windowControllers.first?.window }
                    continue
                }
            }
            let document = MarkdownDocument()
            document.fileURL = url
            document.restoredSessionID = tab.id
            var loadedCleanFile = false
            if !tab.isEdited, let url, let data = try? Data(contentsOf: url) {
                loadedCleanFile = (try? document.read(from: data, ofType: "net.daringfireball.markdown")) != nil
            }
            if !loadedCleanFile {
                // Restore edits in memory; never write a recovery copy over the original file.
                document.source = tab.source
                document.encoding = String.Encoding(rawValue: tab.encoding)
                document.diskBaseline = tab.diskBaseline
                document.lastNoticedFingerprint = tab.diskBaseline
            }
            if let url {
                document.fileModificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }
            document.restoredReadingState = tab.readingState
            controller.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            if !loadedCleanFile { document.updateChangeCount(.changeDone) }
            if let window = document.windowControllers.first?.window {
                if let anchor, anchor.tabGroup !== window.tabGroup { anchor.addTabbedWindow(window, ordered: .above) }
                anchor = window
                if tab.id == snapshot.selectedID { selectedWindow = window }
            }
            document.checkDisk()
            restored.append(document)
        }
        let active = launchWindow ?? selectedWindow ?? restored.first?.windowControllers.first?.window
        if let active {
            active.tabGroup?.selectedWindow = active
            active.makeKeyAndOrderFront(nil)
        }
        return restored
    }
}
