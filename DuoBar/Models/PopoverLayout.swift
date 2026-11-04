import Foundation

/// The reorderable modules of the popover, in their saved order.
enum PopoverModule: String, CaseIterable, Hashable {
    case network
    case volume
    case battery
    case systemStats
    case audioOutput
    case audioInput

    static func storedOrder() -> [PopoverModule] {
        StoredOrder.read(PreferenceKeys.moduleOrder)
    }

    static func storeOrder(_ order: [PopoverModule]) {
        StoredOrder.write(order, to: PreferenceKeys.moduleOrder)
    }
}

/// The square stat tiles, in their saved order.
enum SystemStatTile: String, CaseIterable, Hashable {
    case cpu
    case memory
    case storage

    static func storedOrder() -> [SystemStatTile] {
        StoredOrder.read(PreferenceKeys.statTileOrder)
    }

    static func storeOrder(_ order: [SystemStatTile]) {
        StoredOrder.write(order, to: PreferenceKeys.statTileOrder)
    }
}

private enum StoredOrder {
    /// Saved order first; items added in later versions are appended.
    static func read<T: RawRepresentable & CaseIterable & Equatable>(_ key: String) -> [T] where T.RawValue == String {
        let saved = (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(T.init(rawValue:))
        var order: [T] = []
        for item in saved where !order.contains(item) { order.append(item) }
        for item in T.allCases where !order.contains(item) { order.append(item) }
        return order
    }

    static func write<T: RawRepresentable>(_ order: [T], to key: String) where T.RawValue == String {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: key)
    }
}
