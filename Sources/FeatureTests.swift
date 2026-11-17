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
    print("ALL FEATURE CHECKS PASSED")
}
#endif
