import SwiftUI

/// A grid of icons that can be dragged into a new order, like a Home Screen
/// in jiggle mode. Cells sit at computed positions, so a reorder animates
/// every icon to its new place while the dragged one follows the pointer.
/// Used by the Widgets page's rearrange mode and Settings › Shelf › Widget icons.
struct ReorderableIconGrid<Cell: View>: View {
    let ids: [String]
    let columns: Int
    let cellSize: CGSize
    /// Dragging is on (and the icons wiggle); off, cells are left alone.
    var isEditing: Bool = true
    /// Home Screen wiggle while editing; Settings keeps its icons still.
    var wiggles: Bool = true
    let onReorder: ([String]) -> Void
    @ViewBuilder let cell: (String) -> Cell

    @State private var liveOrder: [String]?
    @State private var dragging: String?
    @State private var dragPoint: CGPoint = .zero
    @State private var wiggle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let space = "reorderableGrid"

    private var order: [String] { liveOrder ?? ids }
    private var rows: Int { max((order.count + columns - 1) / columns, 1) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(order, id: \.self) { id in
                let index = order.firstIndex(of: id) ?? 0
                let isDragged = dragging == id
                ZStack {
                    cell(id).allowsHitTesting(!isEditing)
                    // While editing, a plain surface takes the drag instead of the cell's buttons.
                    if isEditing { Color.clear.contentShape(Rectangle()) }
                }
                    .frame(width: cellSize.width, height: cellSize.height)
                    // Only when wiggling: with `wiggles` off (Settings) the
                    // resting pose would leave every icon tilted by 1.6°.
                    .rotationEffect(.degrees(isEditing && wiggles && !isDragged && !reduceMotion ? (wiggle ? 1.6 : -1.6) * (index.isMultiple(of: 2) ? 1 : -1) : 0))
                    .scaleEffect(isDragged ? 1.12 : 1)
                    .opacity(isDragged ? 0.9 : 1)
                    .shadow(color: .black.opacity(isDragged ? 0.45 : 0), radius: 10, y: 6)
                    .gesture(drag(id), including: isEditing ? .all : .subviews)
                    .position(isDragged ? dragPoint : center(of: index))
                    .zIndex(isDragged ? 1 : 0)
                    .accessibilityAction(named: "Move earlier") { move(id, by: -1) }
                    .accessibilityAction(named: "Move later") { move(id, by: 1) }
            }
        }
        .frame(width: CGFloat(columns) * cellSize.width, height: CGFloat(rows) * cellSize.height, alignment: .topLeading)
        .coordinateSpace(name: space)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: order)
        .onAppear { startWiggle() }
        .onChange(of: isEditing) { _, _ in startWiggle() }
    }

    private func center(of index: Int) -> CGPoint {
        CGPoint(x: (CGFloat(index % columns) + 0.5) * cellSize.width,
                y: (CGFloat(index / columns) + 0.5) * cellSize.height)
    }

    private func slot(at point: CGPoint) -> Int {
        let column = min(max(Int(point.x / cellSize.width), 0), columns - 1)
        let row = min(max(Int(point.y / cellSize.height), 0), rows - 1)
        return min(row * columns + column, max(order.count - 1, 0))
    }

    private func drag(_ id: String) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(space))
            .onChanged { value in
                if dragging == nil {
                    dragging = id
                    liveOrder = ids
                    DroppyAudio.playTick()
                }
                dragPoint = value.location
                guard var current = liveOrder, let from = current.firstIndex(of: id) else { return }
                let to = slot(at: value.location)
                guard to != from else { return }
                current.remove(at: from)
                current.insert(id, at: to)
                liveOrder = current
            }
            .onEnded { _ in
                if let liveOrder, liveOrder != ids { onReorder(liveOrder) }
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
                    dragging = nil
                    liveOrder = nil
                }
            }
    }

    /// VoiceOver's way to reorder.
    private func move(_ id: String, by step: Int) {
        var current = ids
        guard let from = current.firstIndex(of: id) else { return }
        let to = min(max(from + step, 0), current.count - 1)
        guard to != from else { return }
        current.remove(at: from)
        current.insert(id, at: to)
        onReorder(current)
    }

    private func startWiggle() {
        guard isEditing, wiggles, !reduceMotion else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { wiggle = false }
            return
        }
        withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) { wiggle = true }
    }
}
