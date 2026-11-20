# Wi-Fi Icon

Wi-Fi Icon is a small macOS menu bar app with a cosmetic Wi-Fi switch. The switch changes the icon and the menu's appearance. Selecting a network updates the preview only. The app never powers Wi-Fi on or off, joins a network, or changes system network settings.

## Install

1. Download **Wi-Fi-Icon-macOS.zip** from [Releases](https://github.com/Lendq/macos-wifi-preview/releases).
2. Unzip it, move **Wi-Fi Icon.app** to Applications, and open it.
3. Click the crossed-out Wi-Fi symbol in the menu bar. To hide the built-in icon, use **System Settings → Menu Bar** or **System Settings → Control Centre**, depending on your macOS version.

The ZIP contains a universal app for Apple silicon and Intel Macs running macOS 14 or later. This build is locally signed and has no Apple notarization. macOS may block it on first launch. [Apple explains how it handles downloaded apps.](https://support.apple.com/en-us/102445)

Open **Other Networks** to refresh the list with a Wi-Fi scan. macOS can require Location Services permission to reveal network names. Use **Allow Location Access…** in the menu if prompted. The preview switch works without that permission. The app ships without bundled network names. It remembers the cosmetic switch, selected network, and previously joined names locally.

Click a network to simulate joining it, or click the connected network to simulate disconnecting. A secured network asks for a test password the first time you join it in the preview. Any nonempty entry works. The app discards the entry immediately and remembers only the network name.

To put a phone hotspot in **Personal Hotspot**, make the phone broadcast its Wi-Fi network, click **Find a hotspot…** or expand **Other Networks**, then right-click the network and choose **Mark as Personal Hotspot**. The menu remembers the label and shows the row when that network is visible. The app uses the regular Wi-Fi scan, so devices discovered only through Apple's Instant Hotspot feature may be absent. Joining a hotspot uses the same cosmetic flow as joining any other network.

## Build

With Xcode Command Line Tools installed, run:

```sh
./build.sh
```

The app and ZIP appear in `build/`.
