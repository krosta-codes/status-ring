import SwiftUI

/// Support for the title that flies from a card into its detail panel's header.
///
/// Cards report their title's global frame (keyed by the title text), the open panel reports
/// its header title's frame in the `detailContent` coordinate space, and both hide their own
/// title while the popover flies a single copy between the two.
struct CardTitleFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct PanelTitleFrameKey: PreferenceKey {
    static var defaultValue: CGRect? { nil }
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

enum DetailTitleSpace {
    static let name = "detailContent"
}

private struct HiddenCardTitleKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct PanelTitleHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The card title currently replaced by the flying copy.
    var hiddenCardTitle: String? {
        get { self[HiddenCardTitleKey.self] }
        set { self[HiddenCardTitleKey.self] = newValue }
    }

    /// True while the panel header title is replaced by the flying copy.
    var panelTitleHidden: Bool {
        get { self[PanelTitleHiddenKey.self] }
        set { self[PanelTitleHiddenKey.self] = newValue }
    }
}

private struct CardTitleModifier: ViewModifier {
    let title: String
    @Environment(\.hiddenCardTitle) private var hidden

    func body(content: Content) -> some View {
        content
            .opacity(hidden == title ? 0 : 1)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: CardTitleFrameKey.self, value: [title: proxy.frame(in: .global)])
            })
    }
}

private struct PanelTitleModifier: ViewModifier {
    @Environment(\.panelTitleHidden) private var hidden

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .background(GeometryReader { proxy in
                Color.clear.preference(
                    key: PanelTitleFrameKey.self,
                    value: proxy.frame(in: .named(DetailTitleSpace.name))
                )
            })
    }
}

extension View {
    /// Marks a card's title so it can fly into the card's detail panel.
    func cardTitle(_ title: String) -> some View { modifier(CardTitleModifier(title: title)) }

    /// Marks a detail panel's header title, the landing spot of the flying title.
    func panelTitle() -> some View { modifier(PanelTitleModifier()) }
}
