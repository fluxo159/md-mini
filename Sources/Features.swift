import AppKit
import CryptoKit
import Darwin

// Handle document navigation before the text view interprets Command-arrow as a caret move.
final class MarkdownWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .keyDown, modifiers == .command,
           attachedSheet == nil, NSApp.modalWindow == nil,
           let tabs = tabbedWindows, tabs.count > 1 {
            switch event.keyCode {
            case 123: selectPreviousTab(nil); return true
            case 124: selectNextTab(nil); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

enum Preferences {
    static let testDomain = "local.jamil.mdmini.tests." + UUID().uuidString
    static let defaults: UserDefaults = {
        if CommandLine.arguments.contains("--feature-test") || CommandLine.arguments.contains("--render-readme") {
            return UserDefaults(suiteName: testDomain)!
        }
        return UserDefaults.standard
    }()
}

struct ViewBookmark: Codable {
    var character: Int
    var offset: Double
}
struct ReadingState: Codable {
    var mode = 0
    var reader: ViewBookmark?
    var editor: ViewBookmark?
    static func load(_ url: URL) -> ReadingState {
        guard let data = Preferences.defaults.data(forKey: "ReadingState." + url.standardizedFileURL.path),
              let state = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return state
    }
    func store(_ url: URL) {
        if let data = try? JSONEncoder().encode(self) {
            Preferences.defaults.set(data, forKey: "ReadingState." + url.standardizedFileURL.path)
        }
    }
    static func capture(_ view: NSTextView) -> ViewBookmark? {
        guard let manager = view.layoutManager, let container = view.textContainer, manager.numberOfGlyphs > 0 else { return nil }
        manager.ensureLayout(for: container)
        let y = view.enclosingScrollView?.contentView.bounds.origin.y ?? 0
        let point = NSPoint(x: 0, y: max(0, y - view.textContainerInset.height))
        let glyph = min(manager.glyphIndex(for: point, in: container), manager.numberOfGlyphs - 1)
        let rect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return ViewBookmark(character: manager.characterIndexForGlyph(at: glyph), offset: Double(y - rect.minY - view.textContainerInset.height))
    }
    static func restore(_ bookmark: ViewBookmark?, in view: NSTextView) {
        guard let bookmark, let manager = view.layoutManager, let container = view.textContainer,
              let scroll = view.enclosingScrollView, !view.string.isEmpty else { return }
        manager.ensureLayout(for: container)
        let character = min(max(0, bookmark.character), (view.string as NSString).length - 1)
        let glyph = manager.glyphIndexForCharacter(at: character)
        let rect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let y = max(0, rect.minY + view.textContainerInset.height + CGFloat(bookmark.offset))
        var bounds = scroll.contentView.bounds
        bounds.origin = NSPoint(x: 0, y: y)
        scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

// Pipe tables use native text blocks, so cells remain selectable and searchable.
enum MarkdownTable {
    static func cells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|"), !value.hasSuffix("\\|") { value.removeLast() }
        var result = [String](), cell = "", escaped = false, code = false
        for character in value {
            if escaped {
                if character != "|" { cell.append("\\") }
                cell.append(character); escaped = false
            } else if character == "\\" { escaped = true }
            else if character == "`" { code.toggle(); cell.append(character) }
            else if character == "|" && !code { result.append(cell.trimmingCharacters(in: .whitespaces)); cell = "" }
            else { cell.append(character) }
        }
        if escaped { cell.append("\\") }
        result.append(cell.trimmingCharacters(in: .whitespaces))
        return result
    }
    static func alignments(_ separator: String, columns: Int) -> [NSTextAlignment]? {
        let values = cells(separator)
        guard values.count == columns, columns > 0,
              values.allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) else { return nil }
        return values.map { $0.hasSuffix(":") ? ($0.hasPrefix(":") ? .center : .right) : .left }
    }
    static func render(_ rows: [[String]], alignments: [NSTextAlignment], size: CGFloat) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        let table = NSTextTable()
        table.numberOfColumns = alignments.count
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.setValue(100, type: .percentageValueType, for: .width)
        for (row, cells) in rows.enumerated() {
            for column in 0..<alignments.count {
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setValue(100 / CGFloat(alignments.count), type: .percentageValueType, for: .width)
                block.setWidth(9, type: .absoluteValueType, for: .padding)
                block.setWidth(0.6, type: .absoluteValueType, for: .border)
                block.setBorderColor(.separatorColor)
                block.backgroundColor = row == 0 ? NSColor.quaternaryLabelColor : (row % 2 == 0 ? NSColor.controlBackgroundColor : NSColor.textBackgroundColor)
                let paragraph = NSMutableParagraphStyle()
                paragraph.textBlocks = [block]
                paragraph.alignment = alignments[column]
                paragraph.lineSpacing = 3
                let text = column < cells.count ? cells[column] : ""
                let value = MarkdownRenderer.inline(text, size: size)
                if row == 0 {
                    value.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: NSRange(location: 0, length: value.length))
                }
                value.append(NSAttributedString(string: "\n"))
                value.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: value.length))
                output.append(value)
            }
        }
        output.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: size)]))
        return output
    }
}

func fingerprint(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

final class FileChangeWatcher {
    private var source: DispatchSourceFileSystemObject?
    init?(url: URL, changed: @escaping () -> Void) {
        let descriptor = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler(handler: changed)
        source.setCancelHandler { Darwin.close(descriptor) }
        self.source = source
        source.resume()
    }
    deinit { source?.cancel() }
}
