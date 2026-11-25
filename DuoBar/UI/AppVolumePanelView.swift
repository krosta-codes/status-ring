import SwiftUI

/// Per-app volume detail panel. Same structure and styling as `AudioDevicePanelView`.
@available(macOS 14.2, *)
struct AppVolumePanelView: View {
    @ObservedObject var store: AppAudioStore
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(localized("Back"))

                Text(localized("App Volume"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Spacer()
            }

            if store.permission == .suspectedDenied {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("Status Ring needs System Audio Recording to change an app's volume."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(localized("Allow System Audio Recording")) {
                        store.openPermissionSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                }
                .padding(.horizontal, 4)
            }

            if store.apps.isEmpty {
                Text(localized("No apps are playing audio"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 76)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.apps) { app in
                            AppVolumeRowView(app: app, store: store)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }

            Divider()

            Button {
                _ = SystemSettingsOpener.open(.sound)
            } label: {
                Text(localized("Sound Settings…"))
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onAppear { store.popoverVisible = true }
        .onDisappear { store.popoverVisible = false }
    }
}

@available(macOS 14.2, *)
private struct AppVolumeRowView: View {
    let app: AppAudioRow
    let store: AppAudioStore

    /// Local value so the thumb follows the drag even before the store republishes.
    @State private var dragValue: Double?

    private var level: Double { dragValue ?? app.setting.volume }

    var body: some View {
        HStack(spacing: 8) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Button {
                        store.setMuted(!app.setting.muted, for: app.id)
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(app.setting.muted ? localized("Unmute") : localized("Mute"))
                    .accessibilityLabel("\(app.setting.muted ? localized("Unmute") : localized("Mute")) \(app.name)")

                    Slider(
                        value: Binding(
                            get: { level },
                            set: { newValue in
                                dragValue = newValue
                                store.setVolume(newValue, for: app.id)
                            }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if !editing { dragValue = nil }
                        }
                    )
                    .controlSize(.mini)
                    .accessibilityLabel("\(localized("Volume")) \(app.name)")
                    .accessibilityValue(localized("%d%%", Int((level * 100).rounded())))

                    outputMenu
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .opacity(app.isPlaying ? 1 : 0.5)
        .contextMenu {
            Button(localized("Reset")) { store.reset(app.id) }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = app.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "app")
                .font(.system(size: 14))
                .frame(width: 18, height: 18)
        }
    }

    private var symbol: String {
        if app.setting.muted || level == 0 { return "speaker.slash.fill" }
        switch level {
        case ..<0.34: return "speaker.wave.1"
        case ..<0.67: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }

    private var currentOutputName: String {
        guard let uid = app.setting.outputUID else { return localized("Follow default") }
        return store.outputs.first { $0.uid == uid }?.name ?? localized("Follow default")
    }

    private var outputMenu: some View {
        Menu {
            Button {
                store.setOutput(nil, for: app.id)
            } label: {
                if app.setting.outputUID == nil {
                    Label(localized("Follow default"), systemImage: "checkmark")
                } else {
                    Text(localized("Follow default"))
                }
            }
            ForEach(store.outputs) { device in
                Button {
                    store.setOutput(device.uid, for: app.id)
                } label: {
                    if app.setting.outputUID == device.uid {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: "speaker.wave.2.circle")
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(app.name)
        .accessibilityValue(currentOutputName)
    }
}
