import SwiftUI

/// Inset tile used by every popover row. The tiles sit inside one shared
/// panel (see `PopoverGlassContainer`), like the modules in Control Center.
/// The parameters are kept so existing call sites compile.
struct PopoverCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .padding(.horizontal, 6)
            .background(shape.fill(.primary.opacity(0.07)))
            .overlay(shape.strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
    }
}

extension View {
    func popoverCardBackground(cornerRadius: CGFloat, fillOpacity: Double) -> some View {
        modifier(PopoverCardBackground())
    }
}

/// The single panel behind all popover tiles: Liquid Glass on macOS 26 and
/// later, a translucent material on older systems.
struct PopoverGlassContainer<Content: View>: View {
    static var cornerRadius: CGFloat { 24 }

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}
