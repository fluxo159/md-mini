import AppKit
import UniformTypeIdentifiers

final class MarkdownRenderer {
    static func inline(_ text: String, size: CGFloat, color: NSColor = .labelColor) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color])
        // Resolve inline markup while preserving a readable native text surface.
        let patterns: [(String, Int)] = [("`([^`]+)`", 1), ("\\*\\*([^*]+)\\*\\*", 2), ("__([^_]+)__", 2), ("(?<!\\*)\\*([^*]+)\\*(?!\\*)", 3), ("\\[([^\\]]+)\\]\\(([^)]+)\\)", 4)]
        for (pattern, style) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: result.string, range: NSRange(location: 0, length: result.length))
            for match in matches.reversed() {
                let label = (result.string as NSString).substring(with: match.range(at: 1))
                let replacement = NSMutableAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color])
                let all = NSRange(location: 0, length: replacement.length)
                if style == 1 { replacement.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor], range: all) }
                if style == 2 { replacement.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: all) }
                if style == 3 { replacement.addAttribute(.font, value: NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask), range: all) }
                if style == 4 {
                    let destination = (result.string as NSString).substring(with: match.range(at: 2))
                    if let url = URL(string: destination), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                        replacement.addAttribute(.link, value: url, range: all)
                    }
                }
                result.replaceCharacters(in: match.range, with: replacement)
            }
        }
        return result
    }
    static func render(_ source: String, size: CGFloat) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        var code = false
        let lines = source.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            let raw = lines[index]
            index += 1
            if !code && raw.contains("|") && index < lines.count,
               let alignments = MarkdownTable.alignments(lines[index], columns: MarkdownTable.cells(raw).count) {
                var rows = [MarkdownTable.cells(raw)]
                index += 1
                while index < lines.count && lines[index].contains("|") && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(MarkdownTable.cells(lines[index])); index += 1
                }
                output.append(MarkdownTable.render(rows, alignments: alignments, size: size))
                continue
            }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { code.toggle(); continue }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = 7
            let line: NSMutableAttributedString
            if code {
                line = NSMutableAttributedString(string: raw, attributes: [.font: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular), .foregroundColor: NSColor.labelColor, .backgroundColor: NSColor.controlBackgroundColor])
                paragraph.paragraphSpacing = 0
            } else if let range = raw.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                let level = raw[range].filter { $0 == "#" }.count
                let headingSize = size + CGFloat(max(2, 16 - level * 3))
                line = inline(String(raw[range.upperBound...]), size: headingSize)
                line.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: headingSize), range: NSRange(location: 0, length: line.length))
                paragraph.paragraphSpacingBefore = 12
            } else if ["---", "***", "___"].contains(trimmed) {
                line = inline("────────────────────────", size: size, color: .separatorColor)
            } else {
                var value = raw
                if let range = value.range(of: "^\\s*[-*+]\\s+", options: .regularExpression) { value.replaceSubrange(range, with: "•  ") }
                value = value.replacingOccurrences(of: "[ ]", with: "☐").replacingOccurrences(of: "[x]", with: "☑")
                if value.hasPrefix("> ") { value = "│  " + value.dropFirst(2) }
                line = inline(value, size: size, color: raw.hasPrefix("> ") ? .secondaryLabelColor : .labelColor)
            }
            line.append(NSAttributedString(string: "\n"))
            line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
            output.append(line)
        }
        return output
    }
}

enum RecentFiles {
    static var urls: [URL] {
        (Preferences.defaults.stringArray(forKey: "RecentMarkdownFiles") ?? []).map { URL(fileURLWithPath: $0) }
    }
    static func remember(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = urls.map { $0.path }.filter { $0 != path }
        paths.insert(path, at: 0)
        Preferences.defaults.set(Array(paths.prefix(20)), forKey: "RecentMarkdownFiles")
    }
    static var pinned: [URL] {
        (Preferences.defaults.stringArray(forKey: "PinnedMarkdownFiles") ?? []).map { URL(fileURLWithPath: $0) }
    }
    static func isPinned(_ url: URL) -> Bool { pinned.contains { $0.standardizedFileURL == url.standardizedFileURL } }
    static func togglePin(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = pinned.map { $0.path }
        if paths.contains(path) { paths.removeAll { $0 == path } } else { paths.append(path) }
        Preferences.defaults.set(paths, forKey: "PinnedMarkdownFiles")
    }
    static func clear() { Preferences.defaults.set([String](), forKey: "RecentMarkdownFiles") }
}

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument, NSTextViewDelegate {
    var source = ""
    var encoding: String.Encoding = .utf8
    var editor: NSTextView!
    var reader: NSTextView!
    var modes: NSSegmentedControl!
    var editorScroll: NSScrollView!
    var readerScroll: NSScrollView!
    var fontSize: CGFloat = 16
    var readingState = ReadingState()
    var currentMode = 0
    var restoringPosition = true
    var positionWork: DispatchWorkItem?
    var observers = [NSObjectProtocol]()
    var watcher: FileChangeWatcher?
    var diskWork: DispatchWorkItem?
    var diskBaseline: Data?
    var lastNoticedFingerprint: Data?
    var hasExternalChange = false
    var changeBanner: NSStackView!
    var changeBannerHeight: NSLayoutConstraint!
    var changeLabel: NSTextField!

    override class var autosavesInPlace: Bool { false }
    override class var readableTypes: [String] { ["net.daringfireball.markdown"] }
    override class var writableTypes: [String] { ["net.daringfireball.markdown"] }
    override init() { super.init(); fileType = "net.daringfireball.markdown" }
    override var windowNibName: NSNib.Name? { nil }

    override func read(from data: Data, ofType typeName: String) throws {
        if let value = String(data: data, encoding: .utf8) { source = value; encoding = .utf8 }
        else if (data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff])), let value = String(data: data, encoding: .utf16) { source = value; encoding = .utf16 }
        else { throw NSError(domain: "MDMini", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать кодировку файла. Поддерживаются UTF-8 и UTF-16."]) }
        diskBaseline = fingerprint(data)
        lastNoticedFingerprint = diskBaseline
        if editor != nil { editor.string = source; refreshReader() }
    }
    override func data(ofType typeName: String) throws -> Data {
        guard let data = source.data(using: encoding) else { throw NSError(domain: "MDMini", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось сохранить текст в исходной кодировке."]) }
        return data
    }
    // A small path dialog avoids depending on the system file-provider save UI.
    func saveAtPath(for operation: NSDocument.SaveOperationType) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Сохранить Markdown"
        alert.informativeText = "Полный путь к файлу (.md). Можно вставить путь из Finder; ~ означает домашнюю папку."
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Отмена")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 520, height: 26))
        let folder = Preferences.defaults.string(forKey: "LastFolder") ?? NSHomeDirectory()
        if operation == .saveToOperation, let url = fileURL {
            field.stringValue = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + " — копия.md").path
        } else { field.stringValue = fileURL?.path ?? (folder as NSString).appendingPathComponent("Заметка.md") }
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        let path = (field.stringValue as NSString).expandingTildeInPath
        guard path.hasPrefix("/"), ["md", "markdown"].contains((path as NSString).pathExtension.lowercased()) else {
            let error = NSAlert(); error.messageText = "Укажите полный путь с расширением .md или .markdown"; error.runModal(); return false
        }
        let url = URL(fileURLWithPath: path)
        if operation == .saveToOperation && url == fileURL {
            let message = NSAlert(); message.messageText = "Для копии выберите другой файл"; message.runModal(); return false
        }
        if FileManager.default.fileExists(atPath: path), url != fileURL || diskDiffers() {
            let replace = NSAlert(); replace.messageText = "Заменить файл «\(url.lastPathComponent)»?"
            replace.informativeText = "Существующее содержимое будет заменено текущим текстом."
            replace.addButton(withTitle: "Отмена"); replace.addButton(withTitle: "Заменить")
            guard replace.runModal() == .alertSecondButtonReturn else { return false }
        }
        do {
            try writeSafely(to: url, ofType: "net.daringfireball.markdown", for: operation)
            if operation != .saveToOperation {
                fileURL = url
                fileType = "net.daringfireball.markdown"
                fileModificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                updateChangeCount(.changeCleared)
                startWatching()
            }
            Preferences.defaults.set(url.deletingLastPathComponent().path, forKey: "LastFolder")
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            RecentFiles.remember(url)
            return true
        } catch { presentError(error); return false }
    }
    override func saveAs(_ sender: Any?) { _ = saveAtPath(for: .saveAsOperation) }
    override func runModalSavePanel(for saveOperation: NSDocument.SaveOperationType, delegate: Any?, didSave didSaveSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        let success = saveAtPath(for: saveOperation)
        if let delegate = delegate as AnyObject?, let selector = didSaveSelector, let implementation = class_getMethodImplementation(object_getClass(delegate), selector) {
            typealias Callback = @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
            unsafeBitCast(implementation, to: Callback.self)(delegate, selector, self, success, contextInfo)
        }
    }
    override func makeWindowControllers() {
        if let url = fileURL { RecentFiles.remember(url); readingState = ReadingState.load(url) }
        let window = MarkdownWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.tabbingIdentifier = "MDMiniDocuments"
        window.tabbingMode = .preferred
        window.minSize = NSSize(width: 440, height: 320)
        window.center()
        window.setFrameAutosaveName("MarkdownWindow")
        let content = NSView()
        window.contentView = content
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)
        modes = NSSegmentedControl(labels: ["Чтение", "Редактор"], trackingMode: .selectOne, target: self, action: #selector(changeMode))
        modes.selectedSegment = fileURL == nil ? 1 : readingState.mode
        modes.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(modes)
        let hint = NSTextField(labelWithString: "⌘O открыть  ·  ⌘S сохранить")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(hint)
        changeLabel = NSTextField(labelWithString: "Файл изменён другой программой")
        changeLabel.font = .systemFont(ofSize: 12)
        changeLabel.lineBreakMode = .byTruncatingTail
        let reload = NSButton(title: "Обновить", target: self, action: #selector(reloadFromDisk(_:)))
        let later = NSButton(title: "Позже", target: self, action: #selector(hideChangeBanner(_:)))
        changeBanner = NSStackView(views: [changeLabel, reload, later])
        changeBanner.spacing = 10
        changeBanner.edgeInsets = NSEdgeInsets(top: 4, left: 20, bottom: 4, right: 20)
        changeBanner.translatesAutoresizingMaskIntoConstraints = false
        changeBanner.isHidden = true
        content.addSubview(changeBanner)
        changeBannerHeight = changeBanner.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([changeBanner.topAnchor.constraint(equalTo: bar.bottomAnchor), changeBanner.leadingAnchor.constraint(equalTo: content.leadingAnchor), changeBanner.trailingAnchor.constraint(equalTo: content.trailingAnchor), changeBannerHeight])
        editorScroll = makeTextView(editable: true)
        readerScroll = makeTextView(editable: false)
        editor = editorScroll.documentView as? NSTextView
        reader = readerScroll.documentView as? NSTextView
        editor.string = source
        editor.delegate = self
        for scroll in [editorScroll!, readerScroll!] {
            content.addSubview(scroll)
            scroll.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: changeBanner.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor), bar.leadingAnchor.constraint(equalTo: content.leadingAnchor), bar.trailingAnchor.constraint(equalTo: content.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 48),
            modes.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20), modes.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            hint.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20), hint.centerYAnchor.constraint(equalTo: bar.centerYAnchor), hint.leadingAnchor.constraint(greaterThanOrEqualTo: modes.trailingAnchor, constant: 12)
        ])
        addWindowController(NSWindowController(window: window))
        currentMode = modes.selectedSegment
        changeMode()
        for scroll in [editorScroll!, readerScroll!] {
            scroll.contentView.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in self?.schedulePositionSave() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.saveReadingPosition(); self?.watcher = nil; self?.diskWork?.cancel()
        })
        startWatching()
    }
    deinit {
        positionWork?.cancel(); diskWork?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
    func makeTextView(editable: Bool) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        text.isEditable = editable
        text.isSelectable = true
        text.isRichText = false
        text.allowsUndo = editable
        text.usesFindBar = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.font = .monospacedSystemFont(ofSize: fontSize - 2, weight: .regular)
        text.textColor = .labelColor
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 28, height: 24)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text
        return scroll
    }
    func refreshReader() { reader.textStorage?.setAttributedString(MarkdownRenderer.render(source, size: fontSize)) }
    @objc func changeMode() {
        if !restoringPosition { saveReadingPosition() }
        restoringPosition = true
        currentMode = modes.selectedSegment
        readingState.mode = currentMode
        let editing = currentMode == 1
        if !editing { refreshReader() }
        editorScroll.isHidden = !editing
        readerScroll.isHidden = editing
        windowControllers.first?.window?.makeFirstResponder(editing ? editor : reader)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.windowControllers.first?.window?.contentView?.layoutSubtreeIfNeeded()
            ReadingState.restore(editing ? self.readingState.editor : self.readingState.reader, in: editing ? self.editor : self.reader)
            self.restoringPosition = false
            if let url = self.fileURL { self.readingState.store(url) }
        }
    }
    func schedulePositionSave() {
        guard !restoringPosition else { return }
        positionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveReadingPosition() }
        positionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func saveReadingPosition() {
        guard !restoringPosition, let url = fileURL, editor != nil else { return }
        readingState.mode = currentMode
        if currentMode == 1 { readingState.editor = ReadingState.capture(editor) }
        else { readingState.reader = ReadingState.capture(reader) }
        readingState.store(url)
    }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(togglePin(_:)) {
            let pinned = fileURL.map { RecentFiles.isPinned($0) } ?? false
            menuItem.title = pinned ? "Открепить текущий файл" : "Закрепить текущий файл"
            menuItem.state = pinned ? .on : .off
            return fileURL != nil
        }
        return super.validateMenuItem(menuItem)
    }
    @objc func togglePin(_ sender: Any?) { if let url = fileURL { RecentFiles.togglePin(url) } }
    func startWatching() {
        watcher = nil
        guard let url = fileURL else { return }
        watcher = FileChangeWatcher(url: url) { [weak self] in self?.scheduleDiskCheck() }
    }
    override func presentedItemDidChange() {
        // NSDocument must not silently reload over the user's edits.
        DispatchQueue.main.async { [weak self] in self?.scheduleDiskCheck() }
    }
    func scheduleDiskCheck() {
        diskWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkDisk() }
        diskWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func diskFingerprint() -> Data? {
        guard let url = fileURL, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return fingerprint(data)
    }
    func diskDiffers() -> Bool { fileURL != nil && diskFingerprint() != diskBaseline }
    func checkDisk() {
        guard fileURL != nil, editor != nil else { return }
        let latest = diskFingerprint()
        guard latest != lastNoticedFingerprint else { return }
        lastNoticedFingerprint = latest
        hasExternalChange = latest != diskBaseline
        if !hasExternalChange { hideChangeBanner(nil); return }
        changeLabel.stringValue = latest == nil ? "Файл удалён или недоступен на диске" : "Файл изменён другой программой"
        changeBannerHeight.constant = 44
        changeBanner.isHidden = false
    }
    @objc func hideChangeBanner(_ sender: Any?) {
        guard changeBanner != nil else { return }
        changeBannerHeight.constant = 0
        changeBanner.isHidden = true
    }
    @objc func reloadFromDisk(_ sender: Any?) {
        guard let url = fileURL else { return }
        if isDocumentEdited {
            let alert = NSAlert()
            alert.messageText = "В документе есть ваши несохранённые правки"
            alert.informativeText = "Можно сохранить их в отдельную копию перед обновлением или заменить текст версией с диска."
            alert.addButton(withTitle: "Отмена")
            alert.addButton(withTitle: "Сохранить копию…")
            alert.addButton(withTitle: "Заменить мои правки")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn { return }
            if response == .alertSecondButtonReturn && !saveAtPath(for: .saveToOperation) { return }
        }
        saveReadingPosition()
        restoringPosition = true
        do {
            let data = try Data(contentsOf: url)
            try read(from: data, ofType: fileType ?? "net.daringfireball.markdown")
            fileModificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            undoManager?.removeAllActions()
            updateChangeCount(.changeCleared)
            hasExternalChange = false
            hideChangeBanner(nil)
            changeMode()
        } catch { restoringPosition = false; presentError(error) }
    }
    override func save(_ sender: Any?) {
        guard let url = fileURL else { super.save(sender); return }
        if diskDiffers() {
            let alert = NSAlert()
            alert.messageText = "Файл на диске изменён или удалён"
            alert.informativeText = "Сохраните ваши правки в отдельную копию или явно замените файл на диске."
            alert.addButton(withTitle: "Отмена")
            alert.addButton(withTitle: "Сохранить копию…")
            alert.addButton(withTitle: "Заменить файл")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn { _ = saveAtPath(for: .saveToOperation); return }
            guard response == .alertThirdButtonReturn else { return }
        }
        do {
            try writeSafely(to: url, ofType: fileType ?? "net.daringfireball.markdown", for: .saveOperation)
            fileModificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            updateChangeCount(.changeCleared)
        } catch { presentError(error) }
    }
    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
        if saveOperation != .saveToOperation {
            diskBaseline = fingerprint(try data(ofType: typeName))
            lastNoticedFingerprint = diskBaseline
            hasExternalChange = false
            hideChangeBanner(nil)
        }
    }
    @objc func toggleMode(_ sender: Any?) { modes.selectedSegment = 1 - modes.selectedSegment; changeMode() }
    @objc func bigger(_ sender: Any?) { fontSize = min(32, fontSize + 1); updateFonts() }
    @objc func smaller(_ sender: Any?) { fontSize = max(11, fontSize - 1); updateFonts() }
    func updateFonts() { editor.font = .monospacedSystemFont(ofSize: fontSize - 2, weight: .regular); if modes.selectedSegment == 0 { refreshReader() } }
    func textDidChange(_ notification: Notification) { source = editor.string; updateChangeCount(.changeDone) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let pinned = RecentFiles.pinned
        let recent = RecentFiles.urls.filter { !RecentFiles.isPinned($0) }
        let urls = pinned + recent
        if urls.isEmpty {
            let empty = NSMenuItem(title: "Пока нет недавних файлов", action: nil, keyEquivalent: "")
            menu.addItem(empty)
        } else {
            for (index, url) in urls.enumerated() {
                if index == 0 && !pinned.isEmpty {
                    let heading = NSMenuItem(title: "Закреплённые", action: nil, keyEquivalent: "")
                    menu.addItem(heading)
                }
                if index == pinned.count && !pinned.isEmpty && !recent.isEmpty { menu.addItem(.separator()) }
                let duplicateName = urls.filter { $0.lastPathComponent == url.lastPathComponent }.count > 1
                let title = duplicateName ? "\(url.lastPathComponent) — \(url.deletingLastPathComponent().lastPathComponent)" : url.lastPathComponent
                let entry = NSMenuItem(title: title, action: #selector(openRecent(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = url
                entry.toolTip = url.path
                menu.addItem(entry)
            }
            menu.addItem(.separator())
        }
        let clear = NSMenuItem(title: "Очистить недавние", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }
    @objc func clearRecent(_ sender: Any?) { RecentFiles.clear() }
    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
            else { RecentFiles.remember(url) }
        }
    }

    @objc func openPath(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Открыть Markdown"
        alert.informativeText = "Вставьте полный путь к .md-файлу."
        alert.addButton(withTitle: "Открыть"); alert.addButton(withTitle: "Отмена")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 520, height: 26))
        field.stringValue = Preferences.defaults.string(forKey: "LastFolder") ?? NSHomeDirectory()
        alert.accessoryView = field; alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let url = URL(fileURLWithPath: (field.stringValue as NSString).expandingTildeInPath)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
            else { Preferences.defaults.set(url.deletingLastPathComponent().path, forKey: "LastFolder") }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        for document in NSDocumentController.shared.documents {
            (document as? MarkdownDocument)?.saveReadingPosition()
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppKit may also insert its own recent-documents menu at launch.
        // Keep one visible, localized list with persistent pinned files and history.
        if let fileMenu = NSApp.mainMenu?.item(at: 1)?.submenu {
            for entry in fileMenu.items {
                guard let submenu = entry.submenu, submenu.delegate !== self else { continue }
                if submenu.items.contains(where: { $0.action == #selector(NSDocumentController.clearRecentDocuments(_:)) }) {
                    fileMenu.removeItem(entry)
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

func item(_ title: String, _ action: Selector?, _ key: String = "") -> NSMenuItem { NSMenuItem(title: title, action: action, keyEquivalent: key) }
func menu(_ title: String, _ items: [NSMenuItem], in parent: NSMenu) {
    let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: title)
    for i in items { submenu.addItem(i) }
    entry.submenu = submenu
    parent.addItem(entry)
}

if CommandLine.arguments.contains("--render-readme") {
    #if README_PREVIEW
    try renderReadmePreviews()
    #else
    print("README previews require a build with -D README_PREVIEW")
    exit(1)
    #endif
} else if CommandLine.arguments.contains("--feature-test") {
    #if FEATURE_TEST
    try runFeatureTests()
    #else
    print("Feature tests require a build with -D FEATURE_TEST")
    exit(1)
    #endif
} else if CommandLine.arguments.contains("--self-test") {
    let doc = MarkdownDocument()
    let sample = "# Привет\n\n**Жирный** и `код`\n- [x] Готово\n[Ссылка](https://example.com)\n```swift\nlet x = 1\n```\n"
    try doc.read(from: Data(sample.utf8), ofType: "Markdown")
    let savedUTF8 = try doc.data(ofType: "Markdown")
    precondition(savedUTF8 == Data(sample.utf8))
    let rendered = MarkdownRenderer.render(sample, size: 16)
    precondition(rendered.string.contains("Привет") && rendered.string.contains("☑ Готово"))
    precondition(!rendered.string.contains("**") && rendered.string.contains("let x = 1"))
    let utf16 = sample.data(using: .utf16)!
    try doc.read(from: utf16, ofType: "Markdown")
    let savedUTF16 = try doc.data(ofType: "Markdown")
    precondition(savedUTF16 == utf16)
    do { try doc.read(from: Data([0xff, 0xff, 0xff]), ofType: "Markdown"); fatalError("Invalid encoding accepted") } catch {}
    print("PASS: UTF-8/UTF-16 round trips, invalid encoding rejection, Markdown rendering")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    let main = NSMenu()
    menu("MD Mini", [item("О MD Mini", #selector(NSApplication.orderFrontStandardAboutPanel(_:))), .separator(), item("Скрыть MD Mini", #selector(NSApplication.hide(_:)), "h"), .separator(), item("Завершить MD Mini", #selector(NSApplication.terminate(_:)), "q")], in: main)
    menu("Файл", [item("Новый", #selector(NSDocumentController.newDocument(_:)), "n"), item("Открыть…", #selector(NSDocumentController.openDocument(_:)), "o"), .separator(), item("Закрыть", #selector(NSWindow.performClose(_:)), "w"), item("Сохранить", #selector(NSDocument.save(_:)), "s"), item("Сохранить как…", #selector(NSDocument.saveAs(_:)), "S")], in: main)
    let find = item("Найти…", #selector(NSTextView.performFindPanelAction(_:)), "f"); find.tag = NSTextFinder.Action.showFindInterface.rawValue
    menu("Правка", [item("Отменить", Selector(("undo:")), "z"), item("Повторить", Selector(("redo:")), "Z"), .separator(), item("Вырезать", #selector(NSText.cut(_:)), "x"), item("Копировать", #selector(NSText.copy(_:)), "c"), item("Вставить", #selector(NSText.paste(_:)), "v"), item("Выделить всё", #selector(NSText.selectAll(_:)), "a"), .separator(), find], in: main)
    menu("Вид", [item("Чтение / редактор", #selector(MarkdownDocument.toggleMode(_:)), "e"), item("Увеличить текст", #selector(MarkdownDocument.bigger(_:)), "+"), item("Уменьшить текст", #selector(MarkdownDocument.smaller(_:)), "-")], in: main)
    let previousTab = item("Предыдущая вкладка", #selector(NSWindow.selectPreviousTab(_:)), String(UnicodeScalar(NSLeftArrowFunctionKey)!))
    let nextTab = item("Следующая вкладка", #selector(NSWindow.selectNextTab(_:)), String(UnicodeScalar(NSRightArrowFunctionKey)!))
    main.item(at: 3)?.submenu?.addItem(.separator())
    main.item(at: 3)?.submenu?.addItem(previousTab)
    main.item(at: 3)?.submenu?.addItem(nextTab)
    let pathItem = item("Открыть по пути…", #selector(AppDelegate.openPath(_:)), "O")
    pathItem.target = delegate
    main.item(at: 1)?.submenu?.insertItem(pathItem, at: 2)
    let pinItem = item("Закрепить / открепить текущий файл", #selector(MarkdownDocument.togglePin(_:)), "d")
    main.item(at: 1)?.submenu?.insertItem(pinItem, at: 3)
    let recentMenu = NSMenu(title: "Недавние файлы")
    recentMenu.delegate = delegate
    delegate.menuNeedsUpdate(recentMenu)
    let recentItem = NSMenuItem(title: "Недавние файлы", action: nil, keyEquivalent: "")
    recentItem.submenu = recentMenu
    main.item(at: 1)?.submenu?.insertItem(recentItem, at: 3)
    app.mainMenu = main
    withExtendedLifetime(delegate) { app.run() }
}
