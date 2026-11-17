#if README_PREVIEW
import AppKit

// Export the application's own native view without capturing any desktop windows.
func renderReadmePreviews() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mdmini-preview-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: folder)
        Preferences.defaults.removePersistentDomain(forName: Preferences.testDomain)
    }
    let data = try Data(contentsOf: base.appendingPathComponent("examples/Welcome.md"))
    let file = folder.appendingPathComponent("Welcome.md")
    try data.write(to: file)
    let document = MarkdownDocument()
    document.fileURL = file
    try document.read(from: data, ofType: "net.daringfireball.markdown")
    document.makeWindowControllers()
    let window = document.windowControllers[0].window!
    window.setContentSize(NSSize(width: 1000, height: 740))
    window.title = "Welcome.md"
    func export(_ filename: String, mode: Int, dark: Bool) throws {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        document.modes.selectedSegment = mode
        document.changeMode()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let content = window.contentView!
        content.layoutSubtreeIfNeeded()
        let text = mode == 0 ? document.reader! : document.editor!
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        let view = content.superview ?? content
        view.displayIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: base.appendingPathComponent("docs/images/" + filename))
    }
    try export("reading-dark.png", mode: 0, dark: true)
    try export("editing-light.png", mode: 1, dark: false)
    document.close()
    print("Exported native reading and editing previews")
}
#endif
