import SwiftUI

/// Control Center style module: each row is its own Liquid Glass tile on
/// macOS 26 and later, grouped by `PopoverGlassContainer`. Older systems get a
/// translucent inset tile. The parameters are kept so existing call sites compile.
struct PopoverCardBackground: ViewModifier {
    static let cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .padding(.horizontal, 4)
                .glassEffect(.regular.interactive(), in: shape)
                .background(ModuleDropShadow(shape: shape))
        } else {
            content
                .padding(.horizontal, 4)
                .background(shape.fill(.primary.opacity(0.08)))
                .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// Drop shadow drawn only outside a module's shape, so the translucent glass
/// is not darkened from below. Separates the floating modules from the desktop.
struct ModuleDropShadow<S: Shape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(Color.black)
            .shadow(color: .black.opacity(0.45), radius: 9, y: 4)
            .mask {
                Rectangle()
                    .padding(-40)
                    .overlay(shape.fill(Color.black).blendMode(.destinationOut))
                    .compositingGroup()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    func popoverCardBackground(cornerRadius: CGFloat, fillOpacity: Double) -> some View {
        modifier(PopoverCardBackground())
    }
}

/// Round icon badge as used by Control Center modules: white with a blue
/// glyph while the feature is active, frosted otherwise.
struct ControlIconBadge<Glyph: View>: View {
    var isActive: Bool
    var size: CGFloat = 30
    @ViewBuilder var glyph: () -> Glyph

    var body: some View {
        glyph()
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(isActive ? Color.white : Color.primary.opacity(0.14)))
    }
}

/// Large glass module used for the detail views (Wi-Fi, audio devices),
/// like the expanded Wi-Fi module in Control Center.
struct ControlModuleBackground: ViewModifier {
    var cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .background(ModuleDropShadow(shape: shape))
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}

/// Groups the floating glass modules so they render together. There is no
/// panel behind them, as in Control Center; each module draws its own drop
/// shadow to separate it from the desktop.
struct PopoverGlassContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}
