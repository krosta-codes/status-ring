#if DEBUG
import Foundation

enum MarketingCaptureMode {
    static let stateNotification = Notification.Name("com.jurek.statusring.debug.marketing-state")
    static let popoverNotification = Notification.Name("com.jurek.statusring.debug.marketing-popover")

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--marketing-capture")
    }

    static var initialState: String {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--marketing-state=") }?
            .dropFirst("--marketing-state=".count)
            .description ?? "hero"
    }

    static var opensPopover: Bool {
        ProcessInfo.processInfo.arguments.contains("--marketing-popover")
    }
}
#endif
