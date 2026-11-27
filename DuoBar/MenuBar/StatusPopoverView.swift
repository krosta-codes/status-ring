import AppKit
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject private var statusStore: SystemStatusStore
    @ObservedObject private var presentation = PopoverPresentationState.shared
    @ObservedObject private var updates = UpdateService.shared
    @AppStorage(PreferenceKeys.showBatteryPercentage) private var showBatteryPercentage = true
    @AppStorage(PreferenceKeys.batteryColorCoding) private var batteryColorCoding = false
    @State private var detail: PopoverDetail?
    @State private var mainContentSize: CGSize = .zero
    /// Links a row to its detail module so the row itself expands to the top
    /// and retracts back into its slot, like Control Center.
    @Namespace private var detailNamespace
    /// Detail content fades in behind the surface growth (see `showDetail`).
    @State private var detailContentVisible = true
    @ObservedObject private var commandKey = CommandKeyMonitor.shared
    @StateObject private var moduleOrder = ReorderController(
        axis: .vertical,
        order: PopoverModule.storedOrder(),
        onOrderChange: PopoverModule.storeOrder
    )
    @StateObject private var tileOrder = ReorderController(
        axis: .horizontal,
        order: SystemStatTile.storedOrder(),
        onOrderChange: SystemStatTile.storeOrder
    )
    private let onClose: () -> Void
    /// Type-erased `AppAudioStore` (macOS 14.2+); nil on older systems.
    private let appAudioStore: AnyObject?

    init(statusStore: SystemStatusStore, appAudioStore: AnyObject? = nil, onClose: @escaping () -> Void) {
        self.statusStore = statusStore
        self.appAudioStore = appAudioStore
        self.onClose = onClose
    }

    /// Holding ⌘ lets the modules and the stat tiles be dragged into a new order.
    private var isReordering: Bool {
        commandKey.isPressed && detail == nil
    }

    var body: some View {
        PopoverGlassContainer {
            // The main content stays laid out underneath so the panel keeps its
            // size; Nearby Networks takes over the whole panel like the Wi-Fi
            // detail view in Control Center.
            // Glass tiles ignore a parent's opacity, so the main content is
            // removed while a detail panel is open; the measured size keeps the
            // panel from resizing, like the Control Center detail views.
            ZStack {
                if let detail {
                    // The module's surface grows from the card into the panel. Its content
                    // is laid out at the final size and pinned top-leading, so the growing
                    // surface reveals it instead of stretching it, and it fades in just
                    // behind the growth.
                    detailPanel(detail)
                        .padding(14)
                        .frame(
                            width: max(0, mainContentSize.width - 28),
                            height: max(0, mainContentSize.height - 28),
                            alignment: .top
                        )
                        .opacity(detailContentVisible ? 1 : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .modifier(ControlModuleBackground())
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .matchedGeometryEffect(id: detail, in: detailNamespace)
                        .padding(14)
                        .frame(width: mainContentSize.width, height: mainContentSize.height)
                        .transition(.opacity)
                } else {
                    panelContent
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear { mainContentSize = proxy.size }
                                    .onChange(of: proxy.size) { mainContentSize = $0 }
                            }
                        )
                        // The cards step back slightly as the panel comes forward.
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .onChange(of: presentation.isShown) { isShown in
            if !isShown {
                detail = nil
                presentation.isDetailOpen = false
            }
        }
        .onChange(of: presentation.retractRequest) { _ in
            showDetail(nil)
        }
        .opacity(presentation.isShown ? 1 : 0)
        .animation(presentation.isShown ? PopoverMotion.openOpacity : PopoverMotion.close, value: presentation.isShown)
        .blur(radius: presentation.isShown ? 0 : presentation.hiddenBlur)
        .animation(presentation.isShown ? PopoverMotion.openBlur : PopoverMotion.close, value: presentation.isShown)
        // Opening reads as dropping out of the menu bar icon: a short settle downward from the top edge.
        .scaleEffect(presentation.isShown ? 1 : 0.96, anchor: .top)
        .offset(y: presentation.isShown ? 0 : -8)
        .animation(presentation.isShown ? PopoverMotion.openSettle : PopoverMotion.close, value: presentation.isShown)
    }

    private var panelContent: some View {
        VStack(spacing: 8) {
            ReorderableStack(
                controller: moduleOrder,
                isEditing: isReordering,
                catchesDrag: { $0 != .systemStats },
                content: module
            )

            #if DEBUG
            DebugStatusSimulatorView(statusStore: statusStore)
            #endif

            // Development diagnostics belong in the dedicated DEBUG diagnostics
            // surface, never in the production status-card hierarchy.
            HStack(spacing: 6) {
                settingsAction

                Spacer()

                if let release = updates.available {
                    Button("Update to \(release.tag)") { updates.installUpdate() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }

                Button(localized("Quit Status Ring")) {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .popoverCardBackground(cornerRadius: 17, fillOpacity: 0.045)
        }
        .padding(14)
        .frame(width: 312)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            commandKey.start()
        }
        .onChange(of: presentation.isShown) { isShown in
            if isShown { commandKey.start() }
        }
    }

    @ViewBuilder
    private func module(_ module: PopoverModule) -> some View {
        switch module {
        case .network:
            StatusRow(
                symbol: networkSymbol,
                title: localized("Network"),
                detail: networkDetail,
                speedText: networkSpeedText,
                stateText: networkState,
                tint: .primary,
                isIconActive: statusStore.status.network.isConnected,
                accessory: .disclosure,
                trailing: wifiPowerToggle,
                onActivate: { showDetail(.network) },
                activationHint: localized("Browse nearby Wi-Fi networks")
            )
            .matchedGeometryEffect(id: PopoverDetail.network, in: detailNamespace)
        case .volume:
            VolumeStatusRow(
                volume: statusStore.status.audio.volume,
                hasOutputDevice: statusStore.status.audio.defaultOutput != nil,
                playbackDeviceIdentifier: statusStore.status.audio.defaultOutput?.uid,
                onSetVolume: statusStore.setVolume,
                onSetMuted: statusStore.setMuted,
                onShowApps: canShowAppVolume ? { showDetail(.apps) } : nil
            )
            .matchedGeometryEffect(id: PopoverDetail.apps, in: detailNamespace)
        case .battery:
            Button(action: openBatterySettings) {
                BatteryStatusRow(
                    battery: statusStore.status.battery,
                    showPercentage: showBatteryPercentage,
                    showsDisclosure: true,
                    timeEstimate: statusStore.batteryTimeEstimate
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityHint(localized("Open Battery Settings"))
        case .systemStats:
            ReorderableStack(
                controller: tileOrder,
                isEditing: isReordering,
                crossAxis: CrossAxisDragForwarder(
                    changed: { value in
                        moduleOrder.dragChanged(
                            .systemStats,
                            location: value.location,
                            startLocation: value.startLocation
                        )
                    },
                    ended: { moduleOrder.dragEnded() }
                )
            ) { tile in
                SystemStatTileView(tile: tile, stats: statusStore.systemStats)
            }
        case .audioOutput:
            StatusRow(
                symbol: audioOutputSymbol,
                title: localized("Audio Output"),
                detail: audioOutputDetail,
                stateText: audioOutputState,
                tint: .primary,
                accessory: .disclosure,
                onActivate: { showDetail(.output) },
                activationHint: localized("Select audio output")
            )
            .matchedGeometryEffect(id: PopoverDetail.output, in: detailNamespace)
        case .audioInput:
            StatusRow(
                symbol: audioInputSymbol,
                title: localized("Audio Input"),
                detail: audioInputDetail,
                stateText: audioInputState,
                tint: .primary,
                accessory: .disclosure,
                onActivate: { showDetail(.input) },
                activationHint: localized("Select audio input")
            )
            .matchedGeometryEffect(id: PopoverDetail.input, in: detailNamespace)
        }
    }

    @ViewBuilder
    private var settingsAction: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                settingsLabel
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
                onClose()
            })
        } else {
            Button(action: openSettingsFromApplicationMenu) {
                settingsLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var settingsLabel: some View {
        Label(localized("Settings"), systemImage: "gearshape")
    }

    private func openSettingsFromApplicationMenu() {
        NSApp.activate(ignoringOtherApps: true)
        if let settingsItem = findSettingsMenuItem(in: NSApp.mainMenu), let action = settingsItem.action {
            NSApp.sendAction(action, to: settingsItem.target, from: settingsItem)
        }
        onClose()
    }

    private func findSettingsMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.keyEquivalent == ",", item.keyEquivalentModifierMask.contains(.command) {
                return item
            }
            if let settingsItem = findSettingsMenuItem(in: item.submenu) {
                return settingsItem
            }
        }
        return nil
    }

    private var networkSettingsHint: String {
        SystemSettingsOpener.pane(for: statusStore.status.network) == .network
            ? localized("Open Network Settings")
            : localized("Open Wi-Fi Settings")
    }

    private func openNetworkSettings() {
        _ = SystemSettingsOpener.open(SystemSettingsOpener.pane(for: statusStore.status.network))
        onClose()
    }

    private enum PopoverDetail: Hashable {
        case network
        case output
        case input
        case apps
    }

    /// App Volume needs process taps (macOS 14.2+) and a live store.
    private var canShowAppVolume: Bool {
        if #available(macOS 14.2, *) {
            return appAudioStore is AppAudioStore
        }
        return false
    }

    private func showDetail(_ newDetail: PopoverDetail?) {
        if newDetail != nil, detail == nil {
            detailContentVisible = false
            DispatchQueue.main.async {
                withAnimation(PopoverMotion.detailContentIn) { detailContentVisible = true }
            }
        }
        withAnimation(PopoverMotion.detail) {
            detail = newDetail
        }
        presentation.isDetailOpen = newDetail != nil
    }

    @ViewBuilder
    private func detailPanel(_ detail: PopoverDetail) -> some View {
        switch detail {
        case .network:
            NearbyWiFiPanelView(
                statusStore: statusStore,
                wifiPowerToggle: wifiPowerToggle,
                onBack: { showDetail(nil) },
                onOpenSettings: openNetworkSettings
            )
        case .output:
            AudioDevicePanelView(
                title: localized("Audio Output"),
                devices: statusStore.status.audio.selectableOutputs,
                selectedUID: statusStore.status.audio.defaultOutput?.uid,
                emptyText: localized("No output devices"),
                failureText: localized("Unable to Switch Output"),
                symbol: audioDeviceSymbol,
                onSelect: { statusStore.setDefaultOutput(uid: $0) },
                onBack: { showDetail(nil) },
                onOpenSettings: openSoundSettings
            )
        case .input:
            AudioDevicePanelView(
                title: localized("Audio Input"),
                devices: statusStore.status.audio.selectableInputs,
                selectedUID: statusStore.status.audio.defaultInput?.uid,
                emptyText: localized("No input devices"),
                failureText: localized("Unable to Switch Input"),
                symbol: { _ in "mic" },
                onSelect: { statusStore.setDefaultInput(uid: $0) },
                onBack: { showDetail(nil) },
                onOpenSettings: openSoundSettings
            )
        case .apps:
            if #available(macOS 14.2, *), let store = appAudioStore as? AppAudioStore {
                AppVolumePanelView(store: store, onBack: { showDetail(nil) })
            }
        }
    }

    private func audioDeviceSymbol(_ device: AudioDeviceStatus) -> String {
        switch device.category {
        case .airPods: return "airpodspro"
        case .headphones, .bluetoothAudio: return "headphones"
        case .displayAudio: return "display"
        case .usbAudio, .builtInSpeaker, .other: return "speaker.wave.2"
        }
    }

    private func openWiFiSettings() {
        _ = SystemSettingsOpener.open(.wifi)
        onClose()
    }

    private func openBatterySettings() {
        _ = SystemSettingsOpener.open(.battery)
        onClose()
    }

    private func openSoundSettings() {
        _ = SystemSettingsOpener.open(.sound)
        onClose()
    }

    private var networkSymbol: String {
        let network = statusStore.status.network
        guard network.isConnected else { return "network.slash" }
        if network.hotspot != nil { return "personalhotspot" }
        switch network.transport {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector.horizontal"
        case .other: return "ellipsis.circle"
        case .none: return "network.slash"
        }
    }

    private var networkDetail: String {
        let network = statusStore.status.network
        if statusStore.wifiPowerControlError != nil {
            return localized("Unable to change Wi-Fi power")
        }
        guard network.isAvailable else { return localized("No network interface") }
        guard network.isConnected else {
            return network.isWiFiPoweredOn == false ? localized("Wi-Fi disabled") : localized("Not connected")
        }
        switch network.hotspot {
        case .usb: return localized("Personal Hotspot via USB")
        case .bluetooth: return localized("Personal Hotspot via Bluetooth")
        case .wifi: return network.ssid ?? localized("Personal Hotspot")
        case nil: break
        }
        switch network.transport {
        case .wifi: return network.ssid ?? localized("Network name unavailable")
        case .ethernet: return network.interfaceName ?? localized("Wired connection")
        case .other: return network.interfaceName ?? localized("Active connection")
        case .none: return localized("Not connected")
        }
    }

    private var networkSpeedText: String? {
        guard statusStore.status.network.isConnected,
              let speed = statusStore.networkSpeed else { return nil }
        let down = NetworkSpeedFormatter.compact(speed.downloadBytesPerSecond)
        let up = NetworkSpeedFormatter.compact(speed.uploadBytesPerSecond)
        return "↓\(down) ↑\(up)"
    }

    private var networkState: String {
        let network = statusStore.status.network
        guard network.isAvailable else { return localized("Unavailable") }
        if network.isWiFiPoweredOn == false, !network.isConnected { return localized("Off") }
        guard network.isConnected else { return localized("Offline") }
        if network.hotspot != nil { return localized("Hotspot") }
        switch network.transport {
        case .wifi: return localized("Wi-Fi")
        case .ethernet: return localized("Ethernet")
        case .other: return localized("Connected")
        case .none: return localized("Offline")
        }
    }

    private var wifiPowerToggle: AnyView? {
        guard let wifiPowerState = statusStore.status.network.isWiFiPoweredOn else { return nil }
        return AnyView(
            Toggle(localized("Wi-Fi power"), isOn: Binding(
                get: { wifiPowerState },
                set: { statusStore.setWiFiPower($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel(localized("Wi-Fi power"))
        )
    }

    private var audioOutputSymbol: String {
        guard let output = statusStore.status.audio.defaultOutput else { return "speaker.slash" }
        switch output.category {
        case .airPods: return "airpodspro"
        case .headphones, .bluetoothAudio: return "headphones"
        case .displayAudio: return "display"
        case .usbAudio, .builtInSpeaker, .other: return "speaker.wave.2"
        }
    }

    private var audioOutputDetail: String {
        statusStore.status.audio.defaultOutput?.name ?? localized("No output device")
    }

    private var audioInputSymbol: String {
        statusStore.status.audio.defaultInput == nil ? "mic.slash" : "mic"
    }

    private var audioInputDetail: String {
        statusStore.status.audio.defaultInput?.name ?? localized("No input device")
    }

    private var audioInputState: String {
        guard let input = statusStore.status.audio.defaultInput else { return localized("Unavailable") }
        switch input.transport {
        case .builtIn: return localized("Built-in")
        case .bluetooth, .bluetoothLE: return localized("Bluetooth")
        case .usb: return localized("USB")
        case .hdmi, .displayPort: return localized("Display")
        case .airPlay: return localized("AirPlay")
        case .virtual: return localized("Virtual")
        case .other: return localized("Connected")
        }
    }

    private var audioOutputState: String {
        guard let output = statusStore.status.audio.defaultOutput else { return localized("Unavailable") }
        if output.transport.isBluetooth {
            return output.temporaryGlyph == .airPods ? localized("AirPods") : localized("Bluetooth")
        }
        switch output.transport {
        case .builtIn: return localized("Built-in")
        case .airPlay: return localized("AirPlay")
        case .usb: return localized("USB")
        case .hdmi, .displayPort: return localized("Display")
        case .virtual: return localized("Virtual")
        case .bluetooth, .bluetoothLE: return localized("Bluetooth")
        case .other: return localized("Connected")
        }
    }
}

struct BatteryStatusRow: View {
    let battery: BatteryStatus
    let showPercentage: Bool
    var showsDisclosure = false
    var timeEstimate: BatteryTimeEstimate = .unavailable

    var body: some View {
        HStack(spacing: 11) {
            ControlIconBadge(isActive: false) {
                Image(systemName: symbol)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(localized("Battery"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    if let trailingValue {
                        Text(trailingValue)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                HStack(spacing: 6) {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if let secondaryDetail {
                        Spacer(minLength: 0)
                        Text(secondaryDetail)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .popoverCardBackground(cornerRadius: 11, fillOpacity: 0.045)
    }

    var trailingValue: String? {
        guard showPercentage, let percentage = battery.percentage else { return nil }
        return localized("%d%%", percentage)
    }

    var detail: String {
        guard battery.isAvailable else { return localized("No internal battery") }
        if battery.isFullyCharged { return localized("Fully charged") }
        if battery.isCharging { return localized("Charging") }
        if battery.isPluggedIn { return localized("Charging On Hold") }
        if battery.isLowPowerModeEnabled { return localized("Low Power Mode") }
        return localized("Using battery power")
    }

    var secondaryDetail: String? {
        guard battery.isAvailable else { return nil }
        switch timeEstimate {
        case .toFull(let minutes):
            return localized("%@ to full", BatteryTimeFormatter.duration(minutes: minutes))
        case .toEmpty(let minutes):
            return localized("%@ left", BatteryTimeFormatter.duration(minutes: minutes))
        case .calculating:
            return localized("Calculating…")
        case .unavailable:
            break
        }
        return battery.isPluggedIn ? localized("Using Adapter") : nil
    }

    var symbol: String {
        if battery.isFullyCharged { return "battery.100percent" }
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percentage ?? 0 {
        case 76...100: return "battery.100percent"
        case 51...75: return "battery.75percent"
        case 26...50: return "battery.50percent"
        default: return "battery.25percent"
        }
    }
}

#if DEBUG
private struct DebugStatusSimulatorView: View {
    let statusStore: SystemStatusStore
    @AppStorage(PreferenceKeys.batteryColorCoding) private var batteryColorCoding = false
    @ObservedObject private var adaptiveRingMonitor = AdaptiveRingMonitor.shared

    var body: some View {
        Menu {
            Menu("Simulate") {
                simulationControls
            }

            Menu("Diagnostics") {
                diagnosticItem("Laptop Ring Mode", value: laptopRingModeLabel)
                diagnosticItem("Charging session", value: chargingSessionLabel)
                diagnosticItem("Waiting for full charge", value: waitingForFullChargeLabel)
                diagnosticItem("Adaptive telemetry lease", value: adaptiveRingMonitor.monitoringOwnerCount > 0 ? "Active" : "Inactive")
                diagnosticItem("Adaptive monitor", value: adaptiveRingMonitor.isMonitoring ? "Running" : "Stopped")
                diagnosticItem("Adaptive source", value: adaptiveRingMonitor.debugTestSource.rawValue)
                diagnosticItem("Brightness", value: brightnessLabel)
                diagnosticItem("Adaptive metric", value: adaptiveRingMonitor.state.diagnosticLabel)
                diagnosticItem("Adaptive progress", value: adaptiveProgressLabel)
                diagnosticItem("Final ring target", value: finalRingOverrideLabel)
            }
        } label: {
            HStack {
                Label("Debug Simulator", systemImage: "hammer")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(debugSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .frame(minHeight: 26)
    }

    @ViewBuilder
    private var simulationControls: some View {
        Menu("Battery Level") {
            ForEach(DebugBatteryLevel.allCases) { level in
                Button(level.title) { statusStore.applyDebugBatteryLevel(level) }
            }
        }
        Menu("Battery Power") {
            ForEach(DebugPowerState.allCases) { powerState in
                Button(powerState.rawValue) { statusStore.applyDebugPowerState(powerState) }
            }
        }
        Menu("Low Power Mode") {
            ForEach(DebugLowPowerMode.allCases) { lowPowerMode in
                Button(lowPowerMode.rawValue) { statusStore.applyDebugLowPowerMode(lowPowerMode) }
            }
        }
        Menu("Battery Color Coding") {
            Button("Off") { batteryColorCoding = false }
            Button("On") { batteryColorCoding = true }
        }
        Menu("MacBook Adaptive Ring") {
            Button("Battery / Unplugged") {
                statusStore.applyDebugAdaptiveBatteryBaseline()
                adaptiveRingMonitor.clearDebugSyntheticInput()
            }
            Button("Charging") {
                scheduleAdaptiveChargingSimulation()
            }
            Divider()
            Button("Adaptive — Neutral") { scheduleAdaptive(.neutral) }
            Button("Adaptive — Brightness") { scheduleAdaptive(.brightness50) }
            Button("Adaptive — CPU") { scheduleAdaptive(.cpuHigh) }
            Button("Adaptive — Memory") { scheduleAdaptive(.memoryPressure) }
            Button("Adaptive — Thermal") { scheduleAdaptive(.thermalSerious) }
            Divider()
            Button("Use Live System State") {
                adaptiveRingMonitor.clearDebugSyntheticInput()
                statusStore.restoreLiveStatus()
            }
        }
        Menu("Network") {
            ForEach(DebugNetworkState.allCases) { networkState in
                Button(networkState.rawValue) { statusStore.applyDebugNetworkState(networkState) }
            }
        }
        Menu("Volume") {
            ForEach(DebugVolumeState.allCases) { volumeState in
                Button(volumeState.rawValue) { statusStore.applyDebugVolumeState(volumeState) }
            }
        }
        Menu("Audio Connection") {
            ForEach(DebugAudioDeviceState.allCases) { deviceState in
                Button(deviceState.rawValue) { statusStore.applyDebugAudioDeviceState(deviceState) }
            }
        }
        Divider()
        Button("Restore Live Data") { statusStore.restoreLiveStatus() }
    }

    private func diagnosticItem(_ title: String, value: String) -> some View {
        Button("\(title): \(value)") {}
            .disabled(true)
    }

    private var debugSummary: String {
        "\(laptopRingModeLabel) · \(adaptiveRingMonitor.debugTestSource.rawValue)"
    }

    private var laptopRingModeLabel: String {
        switch statusStore.laptopRingModeState.mode {
        case .battery: "Battery"
        case .adaptive: "Adaptive"
        }
    }

    private var chargingSessionLabel: String {
        guard let start = statusStore.laptopRingModeState.sessionStartPercentage,
              let target = statusStore.laptopRingModeState.targetPercentage
        else { return "None" }
        let waiting = statusStore.laptopRingModeState.isWaitingForFullChargeDelay ? " · waiting for full delay" : ""
        return "\(start)% → \(target)%\(waiting)"
    }

    private var waitingForFullChargeLabel: String {
        statusStore.laptopRingModeState.isWaitingForFullChargeDelay ? "Yes" : "No"
    }

    private var brightnessLabel: String {
        guard let availability = adaptiveRingMonitor.brightnessSnapshot?.availability else { return "Sampling…" }
        switch availability {
        case .available(let value): return String(format: "%.0f%%", value * 100)
        case .unavailable: return "Unavailable"
        }
    }

    private var adaptiveProgressLabel: String {
        let target = AdaptiveRingVisualTarget(state: adaptiveRingMonitor.state).progress
        return String(format: "%.1f%%", target * 100)
    }

    private var finalRingOverrideLabel: String {
        guard statusStore.usesAdaptiveRing else { return "Battery Ring" }
        let target = AdaptiveRingVisualTarget(state: adaptiveRingMonitor.state).progress
        return String(format: "%.1f%%", target * 100)
    }

    private func scheduleAdaptiveChargingSimulation() {
        Task { @MainActor in
            statusStore.applyDebugAdaptiveChargingBaseline()
            adaptiveRingMonitor.clearDebugSyntheticInput()
            adaptiveQALog("DEBUG controller prepared at 50%; visible Charging percentage preserved; awaiting 80% target")
        }
    }

    private func scheduleAdaptive(_ scenario: AdaptiveRingSyntheticScenario) {
        Task { @MainActor in
            await activateAdaptive(scenario)
        }
    }

    @MainActor
    private func activateAdaptive(_ scenario: AdaptiveRingSyntheticScenario) async {
        if statusStore.laptopRingModeState.mode == .adaptive {
            useAdaptiveSourceScenario(scenario)
            return
        }

        // Direct selection first lets the real Charging presentation settle.
        if statusStore.laptopRingModeState.targetPercentage != DebugBatteryLevel.eighty.rawValue
            || !statusStore.status.battery.isCharging {
            statusStore.applyDebugAdaptiveChargingBaseline()
            try? await Task.sleep(for: .seconds(BatteryChargingAnimationProfile.entranceDuration))
            guard !Task.isCancelled else { return }
        }

        useAdaptiveSourceScenario(scenario)
        await Task.yield()
        statusStore.reachDebugAdaptiveTarget()
        adaptiveQALog("DEBUG crossed controller target without publishing a synthetic battery jump for \(scenario.rawValue)")
    }

    private func useAdaptiveSourceScenario(_ scenario: AdaptiveRingSyntheticScenario) {
        let preference: PerformancePreference = scenario == .memoryPressure ? .memory : .automatic
        adaptiveRingMonitor.useDebugSyntheticInput(
            scenario.input,
            label: scenario.rawValue,
            preference: preference
        )
    }

    private func adaptiveQALog(_ message: String) {
        NSLog("%@", "[DuoBar Adaptive QA] \(message)")
    }
}
#endif
