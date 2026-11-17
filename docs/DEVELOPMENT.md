# Development

The app uses system AppKit, Foundation, CryptoKit, and UniformTypeIdentifiers. There is no package manager or downloaded runtime.

```sh
./build.sh          # output/MD Mini.app, current Mac architecture, macOS 13+ target
./Tools/check.sh    # release build, encoding checks, native feature checks, signature
```

`Sources/FeatureTests.swift` is compiled only with `FEATURE_TEST`; test code is excluded from the release build. Tests use a unique preferences domain and temporary files, then clean them up.

## Documentation assets

```sh
./Tools/make-icon.sh       # vector-based PNG + ICNS
./Tools/render-readme.sh   # native views in light and dark appearance
```

The previews render the app's own views offscreen using `examples/Welcome.md`. They do not capture desktop windows or personal documents. Preview preferences are isolated from normal app data; the preview implementation is excluded from release builds.

The icon's editable source is `Assets/AppIcon.svg`; `Tools/make-icon.swift` draws the matching geometry using AppKit. Keep both synchronized when changing the icon.

## Set the default app explicitly

Finder → Get Info → Open with → MD Mini → Change All.

Alternatively, after installing the app in `~/Applications` or `/Applications`, run this from the repository root:

```sh
swift Tools/set-default.swift
```

This opt-in helper changes the system's default handler for the sample document's Markdown content type. Building and running the editor do not change file associations.

## Release packaging

Build, run checks, and package only the app bundle with `ditto --norsrc --noextattr -c -k --keepParent`. Do not include local preferences, handoff notes, or generated test documents in a release. The current published build is Apple Silicon only and uses an ad hoc signature.

## Session recovery

`Sources/Session.swift` stores tab order, the selected tab, encodings, reading positions, buffers, edited flags, and disk fingerprints. The snapshot is written atomically on normal termination to Application Support/MD Mini/session.json with directory mode 0700 and file mode 0600. Session data is local and excluded from releases and the repository.

`MarkdownApplication.terminate` persists the snapshot before AppKit starts its document-save review. Only after a successful write are dirty flags cleared for termination; restored drafts become edited again. A failed write leaves the app open. Individual tab closing retains the normal document review.

Clean documents reopen from disk; edited buffers recover in memory and retain their original disk fingerprint for conflict checks. Missing files fall back to saved text as edited documents. Existing Finder-opened documents are reused; a saved draft is recovered over a clean in-memory read, while two already-edited buffers remain separate. Empty startup tabs are omitted. The snapshot is written at normal quit, not continuously; latest-edit crash recovery is outside this version.
