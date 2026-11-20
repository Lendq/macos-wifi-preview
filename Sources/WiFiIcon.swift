import AppKit
import CoreLocation
import CoreWLAN
import SwiftUI

private let previewWiFiKey = "PreviewWiFiOn"

private struct PreviewNetwork: Identifiable, Equatable {
    let name: String
    let isSecure: Bool
    var id: String { name }
}

private final class PreviewConnection: ObservableObject {
    private static let selectionKey = "PreviewConnectionSelection"

    enum Transition: Equatable {
        case connecting(String)
        case disconnecting(String)
    }

    @Published private(set) var selected: String?
    @Published private(set) var transition: Transition?
    @Published private(set) var remembered: Set<String>
    private let defaults: UserDefaults
    private var pending: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        remembered = Set(defaults.stringArray(forKey: "PreviewRememberedNetworks") ?? [])
        let previousSelection = defaults.string(forKey: Self.selectionKey)
            ?? defaults.string(forKey: "PreviewSelectedNetwork")
        if let previous = previousSelection, !previous.isEmpty {
            selected = previous
            remembered.insert(previous)
        }
    }

    func useCurrentNetworkInitially(_ name: String?) {
        guard defaults.string(forKey: Self.selectionKey) == nil,
              selected == nil else { return }
        selected = name
    }

    func connect(to name: String) {
        schedule(.connecting(name), delay: 1_800) {
            self.remembered.insert(name)
            self.defaults.set(self.remembered.sorted(), forKey: "PreviewRememberedNetworks")
            self.setSelection(name)
        }
    }

    func disconnect(from name: String) {
        schedule(.disconnecting(name), delay: 900) {
            self.setSelection(nil)
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        transition = nil
    }

    private func setSelection(_ name: String?) {
        selected = name
        defaults.set(name ?? "", forKey: Self.selectionKey)
    }

    private func schedule(_ transition: Transition, delay: UInt64, finish: @escaping () -> Void) {
        cancel()
        self.transition = transition
        pending = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(delay))
            } catch {
                return
            }
            finish()
            self.transition = nil
            self.pending = nil
        }
    }
}

private final class NetworkDiscovery: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Status: Equatable {
        case idle, scanning, permissionNeeded, permissionUnavailable, failed
    }

    private static let hotspotKey = "PreviewPersonalHotspots"

    @Published private(set) var hotspotNames = Set(
        UserDefaults.standard.stringArray(forKey: NetworkDiscovery.hotspotKey) ?? []
    )
    @Published private(set) var currentNetwork: PreviewNetwork?
    @Published private(set) var nearby: [PreviewNetwork] = []
    @Published private(set) var status: Status = .idle

    private let location = CLLocationManager()
    private let queue = DispatchQueue(label: "WiFiIcon.network-scan")
    private var awaitingPermission = false

    override init() {
        super.init()
        location.delegate = self
    }

    func toggleHotspot(_ name: String) {
        if hotspotNames.contains(name) {
            hotspotNames.remove(name)
        } else {
            hotspotNames.insert(name)
        }
        UserDefaults.standard.set(hotspotNames.sorted(), forKey: Self.hotspotKey)
    }

    func loadCachedNetworks() {
        guard status != .scanning, let interface = CWWiFiClient.shared().interface() else { return }
        updateCurrentNetwork(interface)
        let cached = namedNetworks(interface.cachedScanResults() ?? [])
        if !cached.isEmpty {
            nearby = cached
        }
    }

    func scan() {
        guard status != .scanning else { return }
        switch location.authorizationStatus {
        case .notDetermined:
            status = .permissionNeeded
            return
        case .denied, .restricted:
            status = .permissionUnavailable
            return
        default:
            break
        }

        status = .scanning
        queue.async { [weak self] in
            let interface = CWWiFiClient.shared().interface()
            let results = try? interface?.scanForNetworks(withSSID: nil)
            DispatchQueue.main.async {
                guard let self else { return }
                if let interface {
                    self.updateCurrentNetwork(interface)
                }
                if let results {
                    self.nearby = self.namedNetworks(results)
                    self.status = .idle
                } else {
                    self.status = .failed
                }
            }
        }
    }

    func requestPermission() {
        awaitingPermission = true
        NSApp.activate()
        location.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard awaitingPermission || status == .permissionNeeded || status == .permissionUnavailable,
              manager.authorizationStatus != .notDetermined else { return }
        awaitingPermission = false
        scan()
    }

    private func updateCurrentNetwork(_ interface: CWInterface) {
        guard let name = interface.ssid(), !name.isEmpty else {
            currentNetwork = nil
            return
        }
        let security = interface.security()
        currentNetwork = PreviewNetwork(name: name, isSecure: security != .none && security != .unknown)
    }

    private func namedNetworks(_ results: Set<CWNetwork>) -> [PreviewNetwork] {
        var byName: [String: PreviewNetwork] = [:]
        for network in results {
            guard let name = network.ssid, !name.isEmpty else { continue }
            let isSecure = !network.supportsSecurity(.none) || byName[name]?.isSecure == true
            byName[name] = PreviewNetwork(name: name, isSecure: isSecure)
        }
        return byName.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct WiFiPreview: View {
    @AppStorage(previewWiFiKey) private var isOn = false
    @ObservedObject var connection: PreviewConnection
    @ObservedObject var discovery: NetworkDiscovery
    @State private var passwordNetwork: PreviewNetwork?
    @State private var password = ""
    @FocusState private var passwordFocused: Bool
    @State private var showsOtherNetworks = false
    @State private var showsSettings = false

    private var currentNetwork: PreviewNetwork? { discovery.currentNetwork }
    let onChange: (Bool) -> Void
    let onResize: () -> Void

    private var visibleNetworks: [PreviewNetwork] {
        [currentNetwork].compactMap { $0 } + discovery.nearby.filter { $0.name != currentNetwork?.name }
    }

    private var personalHotspots: [PreviewNetwork] {
        visibleNetworks.filter { discovery.hotspotNames.contains($0.name) }
    }

    private var knownNetworks: [PreviewNetwork] {
        visibleNetworks.filter {
            !discovery.hotspotNames.contains($0.name) &&
                ($0.name == currentNetwork?.name || connection.remembered.contains($0.name) || connection.selected == $0.name)
        }
    }

    private var availableNetworks: [PreviewNetwork] {
        let sectionNames = Set((knownNetworks + personalHotspots).map(\.name))
        return visibleNetworks.filter { !sectionNames.contains($0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let passwordNetwork {
                passwordPage(passwordNetwork)
            } else if showsSettings {
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
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(Color.primary.opacity(0.12))
                .allowsHitTesting(false)
        }
        .onChange(of: isOn) { _, value in
            if !value {
                connection.cancel()
                dismissPassword()
                showsOtherNetworks = false
            }
            onChange(value)
            onResize()
        }
        .onChange(of: passwordNetwork?.name) { _, _ in onResize() }
        .onChange(of: connection.selected) { _, _ in onResize() }
        .onChange(of: connection.transition) { _, _ in onResize() }
        .onChange(of: showsOtherNetworks) { _, expanded in
            if expanded { discovery.scan() }
            onResize()
        }
        .onChange(of: discovery.currentNetwork) { _, network in
            connection.useCurrentNetworkInitially(network?.name)
            onResize()
        }
        .onChange(of: discovery.nearby) { _, _ in onResize() }
        .onChange(of: discovery.hotspotNames) { _, _ in onResize() }
        .onChange(of: discovery.status) { _, _ in onResize() }
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

            if isOn {
                networkSections
                Divider()
            }

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

    private var networkSections: some View {
        Group {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Personal Hotspot")
                if !personalHotspots.isEmpty {
                    networkList(personalHotspots)
                } else if showsOtherNetworks {
                    Text("Right-click your phone’s network to mark it as a hotspot.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button("Find a hotspot…") { showsOtherNetworks = true }
                        .buttonStyle(.link)
                }
            }
            Divider()

            if !knownNetworks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(knownNetworks.count == 1 ? "Known Network" : "Known Networks")
                    networkList(knownNetworks)
                }
                Divider()
            }

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
                if !availableNetworks.isEmpty {
                    networkList(availableNetworks)
                }
                switch discovery.status {
                case .scanning:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Looking for networks…")
                    }
                    .foregroundStyle(.secondary)
                case .permissionNeeded:
                    Button("Allow Location Access…") { discovery.requestPermission() }
                case .permissionUnavailable:
                    Text("To see nearby network names, allow Wi-Fi Icon in System Settings → Privacy & Security → Location Services.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .failed:
                    Button("Scan failed. Try again") { discovery.scan() }
                case .idle:
                    if availableNetworks.isEmpty {
                        Text("No other networks found")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func networkList(_ networks: [PreviewNetwork]) -> some View {
        if networks.count > 5 {
            ScrollView { networkRows(networks) }
                .contentMargins(.trailing, 10, for: .scrollContent)
                .frame(height: 165)
        } else {
            networkRows(networks)
        }
    }

    private func networkRows(_ networks: [PreviewNetwork]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(networks) { network in
                networkRow(network)
            }
        }
    }

    private func passwordPage(_ network: PreviewNetwork) -> some View {
        Group {
            Text("Join Wi-Fi Network").font(.headline)
            Text(network.name).fontWeight(.medium)
            SecureField("Password", text: $password)
                .focused($passwordFocused)
                .onAppear { passwordFocused = true }
                .onSubmit { submitPassword(for: network) }
            HStack {
                Spacer()
                Button("Cancel", action: dismissPassword)
                Button("Join") { submitPassword(for: network) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
    }

    private func dismissPassword() {
        password = ""
        passwordNetwork = nil
    }

    private func submitPassword(for network: PreviewNetwork) {
        guard !password.isEmpty else { return }
        dismissPassword()
        connection.connect(to: network.name)
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
            LabeledContent("Selected network", value: isOn ? connection.selected ?? "Disconnected" : "Off")
            if let currentNetwork {
                Button("Use Current Network") { connection.connect(to: currentNetwork.name) }
                    .disabled(!isOn || connection.transition != nil || connection.selected == currentNetwork.name)
            }
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
        let isHotspot = discovery.hotspotNames.contains(name)
        let isSelected = connection.selected == name
        let status: String? = switch connection.transition {
        case .connecting(let target) where target == name: "Connecting…"
        case .disconnecting(let target) where target == name: "Disconnecting…"
        default: nil
        }
        return Button {
            if isSelected {
                connection.disconnect(from: name)
            } else if network.isSecure && !isCurrent && !connection.remembered.contains(name) {
                passwordNetwork = network
            } else {
                connection.connect(to: name)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isHotspot ? "personalhotspot" : "wifi")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected && isOn ? Color.white : Color.primary)
                    .frame(width: 25, height: 25)
                    .background(isSelected && isOn ? Color.accentColor : Color.primary.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name).lineLimit(2)
                    if let status {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()

                if network.isSecure {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Secure network")
                }
                if status != nil {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                } else if isSelected && !isCurrent {
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
        .accessibilityValue(status ?? (isSelected ? "Connected" : ""))
        .accessibilityHint(isSelected ? "Disconnect" : "Connect")
        .contextMenu {
            Button(isHotspot ? "Unmark Personal Hotspot" : "Mark as Personal Hotspot") {
                discovery.toggleHotspot(name)
            }
        }
        .disabled(connection.transition != nil)
    }
}

private final class WiFiPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class MenuBarIcon: NSObject, NSApplicationDelegate {
    private let connection = PreviewConnection()
    private let discovery = NetworkDiscovery()
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

        discovery.loadCachedNetworks()
        connection.useCurrentNetworkInitially(discovery.currentNetwork?.name)
        let hostingView = NSHostingView(rootView: WiFiPreview(
            connection: connection,
            discovery: discovery,
            onChange: { [weak self] in self?.updateIcon(isOn: $0) },
            onResize: { [weak self] in
                DispatchQueue.main.async { self?.positionPanel() }
            }
        ))
        hostingView.safeAreaRegions = []

        let background = NSVisualEffectView()
        background.material = .menu
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
