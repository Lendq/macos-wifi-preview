# Wi-Fi Icon

Wi-Fi Icon is a small macOS menu bar app with a cosmetic Wi-Fi switch. The switch changes the icon and the menu's appearance. Selecting a network updates the preview only. The app never powers Wi-Fi on or off, joins a network, or changes system network settings.

## Install

1. Download **Wi-Fi-Icon-macOS.zip** from [Releases](https://github.com/Lendq/macos-wifi-preview/releases).
2. Unzip it, move **Wi-Fi Icon.app** to Applications, and open it.
3. Click the crossed-out Wi-Fi symbol in the menu bar. To hide the built-in icon, use **System Settings → Menu Bar** or **System Settings → Control Centre**, depending on your macOS version.

The ZIP contains a universal app for Apple silicon and Intel Macs running macOS 14 or later. This build is locally signed and has no Apple notarization. macOS may block it on first launch. [Apple explains how it handles downloaded apps.](https://support.apple.com/en-us/102445)

Network names appear when macOS makes the current connection and cached Wi-Fi results available to the app. Some systems withhold those names. The preview switch still works in that case. The app ships without bundled network names and stores its switch and network selection locally.

## Build

With Xcode Command Line Tools installed, run:

```sh
./build.sh
```

The app and ZIP appear in `build/`.
