import AppKit
import SwiftUI

/// Publishes whether ⌘ is held while DuoBar is active; holding it puts the
/// popover into reorder mode.
@MainActor
final class CommandKeyMonitor: ObservableObject {
    static let shared = CommandKeyMonitor()

    @Published private(set) var isPressed = false
    private var monitor: Any?

    func start() {
        isPressed = NSEvent.modifierFlags.contains(.command)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.isPressed = event.modifierFlags.contains(.command)
            return event
        }
    }
}

/// Order and drag state for one reorderable stack. Frames are in global
/// coordinates so a nested stack can hand a cross-axis drag to its parent.
@MainActor
final class ReorderController<ID: Hashable>: ObservableObject {
    let axis: Axis
    @Published private(set) var order: [ID]
    @Published private(set) var dragged: ID?
    @Published private(set) var pointer: CGFloat = 0
    @Published private(set) var frames: [ID: CGRect] = [:]
    private var grab: CGFloat = 0
    private let onOrderChange: ([ID]) -> Void

    init(axis: Axis, order: [ID], onOrderChange: @escaping ([ID]) -> Void) {
        self.axis = axis
        self.order = order
        self.onOrderChange = onOrderChange
    }

    func updateFrames(_ values: [AnyHashable: CGRect]) {
        var next: [ID: CGRect] = [:]
        for (key, frame) in values {
            if let id = key.base as? ID { next[id] = frame }
        }
        if next != frames { frames = next }
    }

    /// Offset that keeps the dragged item under the pointer while the others
    /// animate into their new slots.
    func offset(for id: ID) -> CGFloat {
        guard dragged == id, let frame = frames[id] else { return 0 }
        return pointer - grab - leading(frame)
    }

    func dragChanged(_ id: ID, location: CGPoint, startLocation: CGPoint) {
        guard let frame = frames[id] else { return }
        if dragged == nil {
            dragged = id
            grab = coordinate(startLocation) - leading(frame)
        }
        guard dragged == id else { return }
        pointer = coordinate(location)

        let target = order.filter { $0 != id }.filter { other in
            guard let otherFrame = frames[other] else { return false }
            return center(otherFrame) < pointer
        }.count
        if let current = order.firstIndex(of: id), current != target {
            withAnimation(.spring(duration: 0.28, bounce: 0.15)) {
                order.remove(at: current)
                order.insert(id, at: target)
            }
            onOrderChange(order)
        }
    }

    func dragEnded() {
        guard dragged != nil else { return }
        withAnimation(.spring(duration: 0.28, bounce: 0.15)) {
            dragged = nil
        }
    }

    private func coordinate(_ point: CGPoint) -> CGFloat { axis == .vertical ? point.y : point.x }
    private func leading(_ frame: CGRect) -> CGFloat { axis == .vertical ? frame.minY : frame.minX }
    private func center(_ frame: CGRect) -> CGFloat { axis == .vertical ? frame.midY : frame.midX }
}

struct ReorderFramesKey: PreferenceKey {
    static var defaultValue: [AnyHashable: CGRect] { [:] }

    static func reduce(value: inout [AnyHashable: CGRect], nextValue: () -> [AnyHashable: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A drag that runs along the other axis, handed to the enclosing stack (for
/// example dragging a stats tile up or down moves the whole tile row).
struct CrossAxisDragForwarder {
    let changed: (DragGesture.Value) -> Void
    let ended: () -> Void
}

/// Stack whose items can be dragged into a new order while `isEditing` is true.
struct ReorderableStack<ID: Hashable, Content: View>: View {
    @ObservedObject var controller: ReorderController<ID>
    var spacing: CGFloat = 8
    let isEditing: Bool
    var cornerRadius: CGFloat = PopoverCardBackground.cornerRadius
    /// Items that contain their own reorderable stack handle drags themselves.
    var catchesDrag: (ID) -> Bool = { _ in true }
    var crossAxis: CrossAxisDragForwarder?
    @ViewBuilder let content: (ID) -> Content

    @State private var lockedAxis: Axis?

    var body: some View {
        let layout = controller.axis == .vertical
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout {
            ForEach(controller.order, id: \.self) { id in
                item(id)
            }
        }
        .onPreferenceChange(ReorderFramesKey.self) { values in
            MainActor.assumeIsolated { controller.updateFrames(values) }
        }
        .onChange(of: isEditing) { editing in
            if !editing {
                lockedAxis = nil
                controller.dragEnded()
                crossAxis?.ended()
            }
        }
    }

    private func item(_ id: ID) -> some View {
        let catches = catchesDrag(id)
        let offset = controller.offset(for: id)
        return content(id)
            .allowsHitTesting(!isEditing || !catches)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ReorderFramesKey.self,
                        value: [AnyHashable(id): proxy.frame(in: .global)]
                    )
                }
            )
            .overlay {
                if isEditing && catches {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            Color.accentColor.opacity(controller.dragged == id ? 0.95 : 0.45),
                            lineWidth: 1.5
                        )
                        .contentShape(Rectangle())
                        .gesture(dragGesture(for: id))
                }
            }
            .offset(
                x: controller.axis == .horizontal ? offset : 0,
                y: controller.axis == .vertical ? offset : 0
            )
            .scaleEffect(controller.dragged == id ? 1.03 : 1)
            .zIndex(controller.dragged == id ? 1 : 0)
    }

    private func dragGesture(for id: ID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if lockedAxis == nil {
                    let horizontal = abs(value.translation.width) > abs(value.translation.height)
                    lockedAxis = horizontal ? .horizontal : .vertical
                }
                if let crossAxis, lockedAxis != controller.axis {
                    crossAxis.changed(value)
                } else {
                    controller.dragChanged(id, location: value.location, startLocation: value.startLocation)
                }
            }
            .onEnded { _ in
                lockedAxis = nil
                controller.dragEnded()
                crossAxis?.ended()
            }
    }
}
