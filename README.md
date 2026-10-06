# Elemelek

[![Build](https://github.com/bosco-rest/elemelek/actions/workflows/build.yml/badge.svg)](https://github.com/bosco-rest/elemelek/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/bosco-rest/elemelek)](https://github.com/bosco-rest/elemelek/releases/latest)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

A native [Matrix](https://matrix.org) client for macOS, written in SwiftUI on top of
[matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk).

- End-to-end encryption, emoji verification, keys restored from the server backup
- Threads, replies, reactions, edits and pinning
- Images and files: paste, drop, captions and a built-in viewer
- Local full-text search across your rooms
- Unread and mention badges, notifications per room, a sidebar that folds to avatars
- Room settings and members; a picture for you or a room from a file or any Fluent emoji
- Link previews fetched on your Mac, never through the homeserver
- English and Polish

## Download

Get the latest DMG from [Releases](https://github.com/bosco-rest/elemelek/releases/latest), open it and drag Elemelek to Applications.

Builds are not notarized yet, so macOS blocks the first launch: open System Settings → Privacy & Security
and choose **Open Anyway** next to Elemelek.

## Requirements

macOS 15 or later. Building needs a Swift 6 toolchain (Xcode or the Command Line Tools).

## Build

```sh
scripts/make-app.sh          # release build -> .build/Elemelek.app
scripts/make-app.sh debug    # debug build
swift test                   # unit tests of the core
```

The script builds with SwiftPM and assembles an ad-hoc signed app bundle. There is no Xcode project.

```sh
scripts/make-dmg.sh          # .build/Elemelek.app -> .build/Elemelek.dmg
```

## Releases

[`build.yml`](.github/workflows/build.yml) builds every push to `main` and every pull request.
Pushing a tag such as `v0.2.0` runs [`release.yml`](.github/workflows/release.yml): it builds that version and
attaches the DMG to a new [release](https://github.com/bosco-rest/elemelek/releases). SwiftPM's downloads are cached by `Package.resolved`
([`setup`](.github/actions/setup/action.yml)); build products are not.

## Layout

```
Sources/Elemelek/      app: models, views, Matrix SDK glue, Keychain session
Sources/ElemelekCore/  pure logic with no UI or SDK: Markdown blocks, syntax highlighting, link finding, settings
Tests/                 tests for the core (`swift test`)
Resources/             app icon, localizations, Fluent Emoji graphics
scripts/               bundling: app and DMG
.github/               CI and releases
```

## Credits

- Icons, avatars, emoji pictures and verification emoji: [Fluent Emoji](https://github.com/microsoft/fluentui-emoji) by Microsoft, MIT.
- Elemelek grew out of earlier experiments with [Cinny](https://github.com/cinnyapp/cinny); it shares no code with it.

## License

[AGPL-3.0](LICENSE)
