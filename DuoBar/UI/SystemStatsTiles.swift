import SwiftUI

/// Square Control Center style modules for CPU, Memory and Storage.
struct SystemStatTileView: View {
    let tile: SystemStatTile
    let stats: SystemStats?

    var body: some View {
        switch tile {
        case .cpu:
            SquareStatTile(
                symbol: "cpu",
                title: localized("CPU"),
                value: stats?.cpuPercent.map { localized("%d%%", $0) } ?? "–",
                detail: localized("Load")
            )
        case .memory:
            SquareStatTile(
                symbol: "memorychip",
                title: localized("Memory"),
                value: stats?.memoryPercent.map { localized("%d%%", $0) } ?? "–",
                detail: stats.map { localized("%@ used", Self.binaryGigabytes($0.memoryUsedBytes)) } ?? ""
            )
        case .storage:
            SquareStatTile(
                symbol: "internaldrive",
                title: localized("Storage"),
                value: stats.map { Self.decimalGigabytes($0.storageAvailableBytes) } ?? "–",
                detail: localized("Available")
            )
        }
    }

    private static func binaryGigabytes(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_073_741_824
        return String(format: gigabytes >= 10 ? "%.0f GB" : "%.1f GB", gigabytes)
    }

    private static func decimalGigabytes(_ bytes: Int64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000
        return String(format: gigabytes >= 100 ? "%.0f GB" : "%.1f GB", gigabytes)
    }
}

private struct SquareStatTile: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                ControlIconBadge(isActive: false, size: 20) {
                    Image(systemName: symbol)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1, contentMode: .fit)
        .popoverCardBackground(cornerRadius: 22, fillOpacity: 0.045)
        .accessibilityElement(children: .combine)
    }
}
