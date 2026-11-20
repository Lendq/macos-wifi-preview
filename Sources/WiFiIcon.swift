import AppKit
import CoreWLAN
import SwiftUI

private let previewWiFiKey = "PreviewWiFiOn"

private struct PreviewNetwork: Identifiable {
    let name: String
    let isSecure: Bool
    var id: String { name }
}

private struct WiFiPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(previewWiFiKey) private var isOn = false
    @AppStorage("PreviewSelectedNetwork") private var savedSelection = ""
    @State private var showsOtherNetworks = false
    @State private var showsSettings = false

    let currentNetwork: PreviewNetwork?
    let otherNetworks: [PreviewNetwork]
    let onChange: (Bool) -> Void
    let onResize: () -> Void

    private var selection: String? {
        otherNetworks.contains { $0.name == savedSelection } ? savedSelection : currentNetwork?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsSettings {
                settingsPage
            } else {
                networksPage
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(width: 300)
        .font(.system(size: 13))
        .fixedSize(horizontal: true, vertical: true)
        .background(colorScheme == .dark ? Color(white: 0.075).opacity(0.84) : .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(Color.primary.opacity(0.12))
                .allowsHitTesting(false)
        }
        .onChange(of: isOn) { _, value in onChange(value) }
        .onChange(of: showsOtherNetworks) { _, _ in onResize() }
        .onChange(of: showsSettings) { _, _ in onResize() }
    }

    private var networksPage: some View {
        Group {
            HStack {
                Text("Wi-Fi").font(.headline)
                Spacer()
                wifiSwitch
            }

            Divider().padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Known Network")
                if let currentNetwork {
                    networkRow(currentNetwork)
                } else {
                    Text("Network name unavailable")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button {
                showsOtherNetworks.toggle()
            } label: {
                HStack {
                    sectionLabel("Other Networks")
                    Spacer()
                    Image(systemName: showsOtherNetworks ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsOtherNetworks ? "Expanded" : "Collapsed")

            if showsOtherNetworks {
                if otherNetworks.isEmpty {
                    Text("No nearby network names available")
                        .foregroundStyle(.secondary)
                } else if otherNetworks.count > 7 {
                    ScrollView { networkList }
                        .frame(height: 200)
                } else {
                    networkList
                }
            }

            Divider()

            HStack {
                menuButton("Wi-Fi Settings…") { showsSettings = true }
                Spacer()
                Menu {
                    Button("Quit Wi-Fi Icon") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel("Wi-Fi Icon options")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    private var networkList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(otherNetworks) { network in
                networkRow(network)
            }
        }
    }

    private var settingsPage: some View {
        Group {
            detailHeader("Wi-Fi Settings")
            Divider()
            HStack {
                Text("Cosmetic Wi-Fi")
                Spacer()
                wifiSwitch
            }
            LabeledContent("Selected network", value: selection ?? "Unavailable")
            Button("Use Current Network") { savedSelection = "" }
                .disabled(currentNetwork == nil || savedSelection.isEmpty)
            Text("Changes apply only to this menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var wifiSwitch: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.40))
                .frame(width: 50, height: 23)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.94))
                        .frame(width: 27, height: 19)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle("Cosmetic Wi-Fi", isOn: $isOn).toggleStyle(.switch)
        }
    }

    private func detailHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Button {
                showsSettings = false
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Back to Networks")
            Text(title).font(.headline)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain)
    }

    private func networkRow(_ network: PreviewNetwork) -> some View {
        let name = network.name
        let isCurrent = name == currentNetwork?.name
        let isSelected = selection == name
        return Button {
            savedSelection = isCurrent ? "" : name
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected && isOn ? Color.white : Color.primary)
                    .frame(width: 25, height: 25)
                    .background(isSelected && isOn ? Color.accentColor : Color.primary.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                Text(name).lineLimit(2)
                Spacer()

                if network.isSecure {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Secure network")
                }
                if isSelected && !isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}

private final class WiFiPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class MenuBarIcon: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: WiFiPanel?
    private var hostingView: NSHostingView<WiFiPreview>?
    private var localMonitor: Any?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let autosaveName = "WiFiOffIndicator"
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position \(autosaveName)": 0])

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = autosaveName
        item.button?.toolTip = "Wi-Fi Icon"
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        statusItem = item
        updateIcon(isOn: UserDefaults.standard.bool(forKey: previewWiFiKey))

        #if VERIFY_PREVIEW
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--show-preview" {
            let reportURL = URL(fileURLWithPath: CommandLine.arguments[2])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let button = self.statusItem?.button else { return }
                let wasHidden = NSApp.isHidden
                button.performClick(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let firstOpen = self.panel?.isVisible == true
                    button.performClick(nil)
                    let closed = self.panel?.isVisible != true
                    button.performClick(nil)
                    let reopened = self.panel?.isVisible == true
                    let report = "App previously hidden: \(wasHidden), currently hidden: \(NSApp.isHidden), first open: \(firstOpen), closed: \(closed), reopened: \(reopened), frame: \(String(describing: self.panel?.frame))"
                    try? report.write(to: reportURL, atomically: true, encoding: .utf8)
                }
            }
        }
        if CommandLine.arguments.contains("--inspect-preview") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.statusItem?.button?.performClick(nil)
            }
        }
        #endif
    }

    private var iconBounds: NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func updateIcon(isOn: Bool) {
        let icon = NSImage(
            systemSymbolName: isOn ? "wifi" : "wifi.slash",
            accessibilityDescription: isOn ? "Wi-Fi preview on" : "Wi-Fi preview off"
        )?.withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        icon?.isTemplate = true
        statusItem?.button?.image = icon
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if let panel {
            let wasVisible = panel.isVisible
            closePanel()
            if wasVisible { return }
        }
        if NSApp.isHidden {
            NSApp.unhideWithoutActivation()
        }

        let interface = CWWiFiClient.shared().interface()
        var currentNetwork: PreviewNetwork?
        if let interface, let name = interface.ssid(), !name.isEmpty {
            let security = interface.security()
            currentNetwork = PreviewNetwork(name: name, isSecure: security != .none && security != .unknown)
        }

        var nearby: [String: PreviewNetwork] = [:]
        for network in interface?.cachedScanResults() ?? [] {
            guard let name = network.ssid, !name.isEmpty, name != currentNetwork?.name else { continue }
            let isSecure = !network.supportsSecurity(.none) || nearby[name]?.isSecure == true
            nearby[name] = PreviewNetwork(name: name, isSecure: isSecure)
        }

        let hostingView = NSHostingView(rootView: WiFiPreview(
            currentNetwork: currentNetwork,
            otherNetworks: nearby.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            onChange: { [weak self] in self?.updateIcon(isOn: $0) },
            onResize: { [weak self] in
                DispatchQueue.main.async { self?.positionPanel() }
            }
        ))
        hostingView.safeAreaRegions = []

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 15
        background.layer?.masksToBounds = true
        hostingView.frame = background.bounds
        hostingView.autoresizingMask = [.width, .height]
        background.addSubview(hostingView)

        var style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        #if VERIFY_PREVIEW
        if CommandLine.arguments.contains("--inspect-preview") {
            style = [.titled, .fullSizeContentView]
        }
        #endif
        let panel = WiFiPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        panel.title = "Wi-Fi Preview"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = background
        self.hostingView = hostingView
        self.panel = panel
        positionPanel()
        panel.makeKeyAndOrderFront(nil)

        #if VERIFY_PREVIEW
        if CommandLine.arguments.contains("--inspect-preview") { return }
        #endif

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 {
                self.closePanel()
                return nil
            }
            if event.type != .keyDown, event.window !== self.panel {
                self.closeIfOutside()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeIfOutside()
        }
    }

    private func positionPanel() {
        guard let panel, let hostingView, let anchor = iconBounds,
              let screen = statusItem?.button?.window?.screen else { return }
        let size = hostingView.fittingSize
        let left = max(screen.frame.minX + 6, min(anchor.maxX + 3 - size.width, screen.frame.maxX - size.width - 6))
        panel.setFrame(NSRect(x: left, y: anchor.minY - size.height - 2, width: size.width, height: size.height), display: true)
    }

    private func closeIfOutside() {
        guard let panel, !panel.frame.contains(NSEvent.mouseLocation),
              iconBounds?.contains(NSEvent.mouseLocation) != true else { return }
        closePanel()
    }

    private func closePanel() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        localMonitor = nil
        outsideClickMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }
}

let application = NSApplication.shared
let delegate = MenuBarIcon()
application.delegate = delegate
application.run()
