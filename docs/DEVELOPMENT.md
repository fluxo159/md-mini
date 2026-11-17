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
