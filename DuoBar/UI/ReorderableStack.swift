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
///
/// During a drag every slot is computed from a snapshot of the item sizes taken
/// when the drag starts, never from live frames: the dragged item's live frame
/// already contains its own offset (a feedback loop that made it jitter), and
/// the other items' live frames are mid-animation after a swap (which made
/// neighbours flip back and forth).
@MainActor
final class ReorderController<ID: Hashable>: ObservableObject {
    let axis: Axis
    @Published private(set) var order: [ID]
    @Published private(set) var dragged: ID?
    @Published private(set) var pointer: CGFloat = 0
    @Published private(set) var frames: [ID: CGRect] = [:]
    private var grab: CGFloat = 0
    private var sizes: [ID: CGFloat] = [:]
    private var origin: CGFloat = 0
    private var gap: CGFloat = 0
    private var orderAtStart: [ID] = []
    private let onOrderChange: ([ID]) -> Void

    init(axis: Axis, order: [ID], onOrderChange: @escaping ([ID]) -> Void) {
        self.axis = axis
        self.order = order
        self.onOrderChange = onOrderChange
    }

    func updateFrames(_ values: [AnyHashable: CGRect]) {
        // Live frames are only needed to start a drag; skipping them during one
        // also avoids a republish on every pointer move.
        guard dragged == nil else { return }
        var next: [ID: CGRect] = [:]
        for (key, frame) in values {
            if let id = key.base as? ID { next[id] = frame }
        }
        if next != frames { frames = next }
    }

    /// Offset that keeps the dragged item under the pointer while the others
    /// animate into their new slots.
    func offset(for id: ID) -> CGFloat {
        guard dragged == id else { return 0 }
        return pointer - grab - slotLeading(id)
    }

    func dragChanged(_ id: ID, location: CGPoint, startLocation: CGPoint) {
        if dragged == nil {
            guard let frame = frames[id], beginDrag() else { return }
            grab = coordinate(startLocation) - leading(frame)
            pointer = coordinate(location)
            dragged = id
        }
        guard dragged == id else { return }
        pointer = coordinate(location)

        // The dragged item takes the slot its centre is in. A neighbour's centre
        // moves to the far side after a swap, so moving back needs a real move
        // back (built-in hysteresis, no flip-flop at the boundary).
        let draggedCenter = pointer - grab + (sizes[id] ?? 0) / 2
        let target = order.filter { $0 != id }.filter { slotCenter($0) < draggedCenter }.count
        if let current = order.firstIndex(of: id), current != target {
            withAnimation(.spring(duration: 0.3, bounce: 0.12)) {
                order.remove(at: current)
                order.insert(id, at: target)
            }
        }
    }

    func dragEnded() {
        guard dragged != nil else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.12)) {
            dragged = nil
        }
        // Persist once per drag instead of on every swap.
        if order != orderAtStart { onOrderChange(order) }
    }

    /// Snapshots sizes, the stack's leading edge and the spacing from the
    /// resting layout. Returns false while frames are incomplete.
    private func beginDrag() -> Bool {
        let resting = order.compactMap { frames[$0] }
        guard resting.count == order.count, let first = resting.first else { return false }
        sizes = Dictionary(uniqueKeysWithValues: zip(order, resting.map(length)))
        origin = leading(first)
        gap = resting.count > 1 ? max(0, leading(resting[1]) - trailing(first)) : 0
        orderAtStart = order
        return true
    }

    private func slotLeading(_ id: ID) -> CGFloat {
        var position = origin
        for other in order {
            if other == id { return position }
            position += (sizes[other] ?? 0) + gap
        }
        return position
    }

    private func slotCenter(_ id: ID) -> CGFloat { slotLeading(id) + (sizes[id] ?? 0) / 2 }

    private func coordinate(_ point: CGPoint) -> CGFloat { axis == .vertical ? point.y : point.x }
    private func leading(_ frame: CGRect) -> CGFloat { axis == .vertical ? frame.minY : frame.minX }
    private func trailing(_ frame: CGRect) -> CGFloat { axis == .vertical ? frame.maxY : frame.maxX }
    private func length(_ frame: CGRect) -> CGFloat { axis == .vertical ? frame.height : frame.width }
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
            // Lift and drop animate on their own; inside the transaction below.
            .animation(.spring(duration: 0.22, bounce: 0.1), value: controller.dragged == id)
            .zIndex(controller.dragged == id ? 1 : 0)
            // The dragged item follows the pointer; animating its slot change on a
            // swap made it jump away and spring back under the cursor.
            .transaction { transaction in
                if controller.dragged == id, transaction.animation != nil, !transaction.disablesAnimations {
                    transaction.animation = nil
                }
            }
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
