# MD Mini 1.0.0

A tiny native Markdown reader and editor for macOS.

- Formatted reading and plain-text editing with native light/dark appearance.
- Markdown tables with column alignment, headings, lists, checkboxes, links, and code blocks.
- The last 20 documents, pinned favorites, and reading-position restoration.
- External-change detection, save-conflict warnings, and a separate-copy option for unsaved edits.
- Search, undo/redo, text sizing, and UTF-8 / BOM-marked UTF-16 files.

## Download

**MD-Mini-macOS-arm64.zip** contains the app for Apple Silicon. Unzip and move **MD Mini.app** into Applications. The interface is in Russian; English and Russian instructions are in the repository.

Targets macOS 13+. Tested on macOS 27.2.1 with Swift 6.4.2. Older macOS versions and Intel Macs have not been tested. The binary is signed ad hoc, not Apple-notarized; macOS may ask for approval before opening it.

New files and Save As currently use a full-path dialog. Images, HTML, Mermaid, and complex nested Markdown are shown as text or simplified. Cloud-sync delays and very large files have not been validated.

The `SHA256SUMS.txt` attachment lists the archive checksum.
