import SwiftUI

/// Timings measured frame by frame from the native Control Center recording.
enum PopoverMotion {
    static let closeDuration: Double = 0.17
    /// Spring used when a module expands into or retracts from its detail view.
    static let detail = Animation.spring(duration: 0.38, bounce: 0.12)
    /// Time to wait for a retract before the popover starts fading.
    static let retractDuration: Double = 0.3
    static let openOpacity = Animation.easeOut(duration: 0.26)
    static let openBlur = Animation.easeOut(duration: 0.30).delay(0.02)
    static let close = Animation.linear(duration: closeDuration)
}

/// Drives the blur + fade used when the popover panel opens and closes.
@MainActor
final class PopoverPresentationState: ObservableObject {
    static let shared = PopoverPresentationState()

    @Published private(set) var isShown = false
    @Published private(set) var hiddenBlur: CGFloat = 10
    /// Set by the popover while a module is expanded into its detail view.
    var isDetailOpen = false
    /// Incremented to ask the popover to retract its expanded module.
    @Published private(set) var retractRequest = 0

    /// Call while the panel is still hidden, before it is ordered front.
    func prepareToShow() { hiddenBlur = 10 }

    func show() { isShown = true }

    /// Returns true when a module was expanded and is now retracting.
    func retractDetailIfNeeded() -> Bool {
        guard isDetailOpen else { return false }
        retractRequest += 1
        return true
    }

    func hide() {
        hiddenBlur = 4
        isShown = false
    }
}
