import SwiftUI

/// Device picker that fills the whole popover panel, in the same style as the
/// Wi-Fi panel (Control Center detail view).
struct AudioDevicePanelView: View {
    let title: String
    let devices: [AudioDeviceStatus]
    let selectedUID: String?
    let emptyText: String
    let failureText: String
    let symbol: (AudioDeviceStatus) -> String
    let onSelect: (String) -> Bool
    let onBack: () -> Void
    let onOpenSettings: () -> Void

    @State private var switchFailed = false

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

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Spacer()
            }

            if devices.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 76)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(devices) { device in
                            deviceButton(device)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }

            if switchFailed {
                Text(failureText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(action: onOpenSettings) {
                Text(localized("Sound Settings…"))
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func deviceButton(_ device: AudioDeviceStatus) -> some View {
        let isSelected = device.uid == selectedUID
        return Button {
            guard !isSelected else { return }
            switchFailed = !onSelect(device.uid)
        } label: {
            HStack(spacing: 10) {
                ControlIconBadge(isActive: isSelected, size: 26) {
                    Image(systemName: symbol(device))
                }
                .font(.system(size: 11, weight: .semibold))

                Text(device.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(isSelected ? 0.09 : 0))
        )
        .accessibilityLabel(device.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
