#if FEATURE_TEST
import AppKit

func runFeatureTests() throws {
    _ = NSApplication.shared
    defer { Preferences.defaults.removePersistentDomain(forName: Preferences.testDomain) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mdmini-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("first.md"), second = root.appendingPathComponent("second.md")
    RecentFiles.remember(first); RecentFiles.remember(second); RecentFiles.togglePin(first)
    RecentFiles.remember(first)
    precondition(RecentFiles.urls == [first, second])
    RecentFiles.clear()
    precondition(RecentFiles.urls.isEmpty && RecentFiles.isPinned(first))
    RecentFiles.togglePin(first)
    precondition(!RecentFiles.isPinned(first))
    print("PASS: pin/recents persistence is separate, duplicates removed")

    let table = MarkdownRenderer.render("| Имя | Баллы |\n| :--- | ---: |\n| **Аня** | 98 |\n| Очень длинная заметка | 42 |\n", size: 16)
    var blocks = [NSTextTableBlock](), alignments = [NSTextAlignment]()
    table.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: table.length)) { value, _, _ in
        if let style = value as? NSParagraphStyle, let block = style.textBlocks.first as? NSTextTableBlock {
            blocks.append(block); alignments.append(style.alignment)
        }
    }
    precondition(blocks.count == 6 && alignments == [.left, .right, .left, .right, .left, .right])
    precondition(table.string.contains("Аня") && !table.string.contains("---:"))
    precondition(MarkdownTable.cells("| a \\| b | `x|y` |") == ["a | b", "`x|y`"])
    let fenced = MarkdownRenderer.render("```\n| A | B |\n| --- | --- |\n```", size: 16)
    precondition(fenced.string.contains("| --- | --- |"))
    print("PASS: real native table blocks, alignment, escaped/code pipes, fenced code")

    let long = (1...200).map { "Строка \($0): место чтения и сохранение позиции." }.joined(separator: "\n")
    try Data(long.utf8).write(to: first)
    let document = MarkdownDocument()
    document.fileURL = first
    try document.read(from: Data(long.utf8), ofType: "net.daringfireball.markdown")
    document.makeWindowControllers()
    document.windowControllers.first?.window?.contentView?.layoutSubtreeIfNeeded()
    document.reader.layoutManager?.ensureLayout(for: document.reader.textContainer!)
    document.restoringPosition = false
    document.currentMode = 0
    document.reader.enclosingScrollView!.contentView.scroll(to: NSPoint(x: 0, y: 1800))
    document.saveReadingPosition()
    let saved = ReadingState.load(first)
    precondition((saved.reader?.character ?? 0) > 0)
    document.reader.enclosingScrollView!.contentView.scroll(to: .zero)
    ReadingState.restore(saved.reader, in: document.reader)
    let restored = ReadingState.capture(document.reader)!
    precondition(restored.character == saved.reader!.character)
    print("PASS: native text layout restores the same visible character")

    precondition(!document.diskDiffers())
    document.source += "\nСобственное сохранение"
    document.updateChangeCount(.changeDone)
    document.save(nil)
    let ownSavedText = try String(contentsOf: first, encoding: .utf8)
    precondition(ownSavedText == document.source && !document.isDocumentEdited && !document.diskDiffers())
    print("PASS: ordinary save writes edits and updates conflict baseline")
    let local = document.source
    document.updateChangeCount(.changeDone)
    try Data("# Обновление извне\nВерсия Codex".utf8).write(to: first, options: .atomic)
    let deadline = Date().addingTimeInterval(3)
    while !document.hasExternalChange && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    precondition(document.hasExternalChange && !document.changeBanner.isHidden)
    precondition(document.source == local && document.isDocumentEdited)
    let disk = try String(contentsOf: first, encoding: .utf8)
    precondition(disk == "# Обновление извне\nВерсия Codex")
    document.hideChangeBanner(nil)
    precondition(document.diskDiffers(), "Dismissal must not disable save conflict protection")
    document.updateChangeCount(.changeCleared)
    document.reloadFromDisk(nil)
    precondition(document.source == "# Обновление извне\nВерсия Codex" && !document.hasExternalChange)
    print("PASS: atomic external replacement detected, unsaved edits preserved, dismissal protects disk, explicit reload")
    document.close()
    try Data("clean at quit".utf8).write(to: first)
    try Data("original on disk".utf8).write(to: second)
    let clean = MarkdownDocument()
    clean.fileURL = first
    try clean.read(from: Data(contentsOf: first), ofType: "net.daringfireball.markdown")
    clean.makeWindowControllers()
    let edited = MarkdownDocument()
    edited.fileURL = second
    try edited.read(from: Data(contentsOf: second), ofType: "net.daringfireball.markdown")
    edited.source = "Unsaved local edits"
    edited.makeWindowControllers()
    edited.updateChangeCount(.changeDone)
    let untitled = MarkdownDocument()
    untitled.source = "An unsaved untitled draft"
    untitled.makeWindowControllers()
    untitled.updateChangeCount(.changeDone)
    let empty = MarkdownDocument()
    empty.makeWindowControllers()
    let snapshot = SessionSnapshot.capture(documents: [clean, edited, untitled, empty], windows: [edited.windowControllers[0].window!, clean.windowControllers[0].window!, untitled.windowControllers[0].window!], selected: clean.windowControllers[0].window)
    precondition(snapshot.tabs.count == 3 && snapshot.tabs[0].path == second.path && snapshot.tabs[1].path == first.path)
    precondition(snapshot.selectedID == snapshot.tabs[1].id)
    let store = SessionStore(directory: root.appendingPathComponent("session"))
    try store.save(snapshot)
    let permissions = (try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as! NSNumber).intValue
    precondition(permissions & 0o777 == 0o600)
    let loaded = try store.load()!
    for document in [clean, edited, untitled, empty] { document.close() }
    try Data("fresh clean file".utf8).write(to: first, options: .atomic)
    try Data("changed externally while app was closed".utf8).write(to: second, options: .atomic)
    let recoveryController = NSDocumentController()
    let recovered = SessionRestorer.restore(loaded, controller: recoveryController)
    precondition(recovered.count == 3)
    precondition(recovered[0].source == "Unsaved local edits" && recovered[0].isDocumentEdited && recovered[0].hasExternalChange)
    precondition(recovered[1].source == "fresh clean file" && !recovered[1].isDocumentEdited)
    precondition(recovered[2].source == "An unsaved untitled draft" && recovered[2].fileURL == nil && recovered[2].isDocumentEdited)
    precondition(recovered[1].windowControllers[0].window!.tabGroup?.selectedWindow === recovered[1].windowControllers[0].window)
    let untouchedDisk = try String(contentsOf: second, encoding: .utf8)
    precondition(untouchedDisk == "changed externally while app was closed")
    _ = SessionRestorer.restore(loaded, controller: recoveryController)
    precondition(recoveryController.documents.count == 3, "Files and untitled recovery drafts must not duplicate")
    for document in recoveryController.documents { document.close() }
    print("PASS: session tab order, active tab, fresh disk reads, unsaved edits/drafts, file privacy, and no duplicate files")
    let finderOpened = MarkdownDocument()
    finderOpened.fileURL = second
    try finderOpened.read(from: Data(contentsOf: second), ofType: "net.daringfireball.markdown")
    recoveryController.addDocument(finderOpened)
    finderOpened.makeWindowControllers()
    _ = SessionRestorer.restore(loaded, controller: recoveryController)
    precondition(finderOpened.source == "Unsaved local edits" && finderOpened.isDocumentEdited && finderOpened.hasExternalChange)
    precondition(recoveryController.documents.filter { $0.fileURL == second }.count == 1)
    for document in recoveryController.documents { document.close() }
    print("PASS: Finder reopening a saved file recovers its unsaved draft without duplicating the file")


    var missing = loaded
    missing.tabs = [loaded.tabs[1]]
    missing.selectedID = missing.tabs[0].id
    try FileManager.default.removeItem(at: first)
    let recoveredMissing = SessionRestorer.restore(missing, controller: recoveryController)
    precondition(recoveredMissing.count == 1 && recoveredMissing[0].source == "clean at quit" && recoveredMissing[0].isDocumentEdited)
    recoveredMissing[0].close()
    try store.save(SessionSnapshot(tabs: [], selectedID: nil))
    let clearedSession = try store.load()!
    precondition(clearedSession.tabs.isEmpty)
    let blocked = root.appendingPathComponent("not-a-directory")
    try Data("blocked".utf8).write(to: blocked)
    do { try SessionStore(directory: blocked).save(loaded); fatalError("Session persistence failure must propagate") } catch {}
    print("PASS: deleted files recover from local snapshot; empty sessions clear; persistence failures propagate")
    print("ALL FEATURE CHECKS PASSED")
}
#endif
