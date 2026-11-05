import Foundation

/// Stable rail width, title-sized active tab and evenly distributed inactive hit areas.
struct TabRailGeometry {
    static let spacing: CGFloat = 2
    let width: CGFloat
    let selectedWidth: CGFloat
    let inactiveWidth: CGFloat
    let selectedOffset: CGFloat
    init(width: CGFloat, count: Int, selectedIndex: Int, preferredSelectionWidth: CGFloat) {
        self.width = max(0, width)
        guard count > 1 else {
            selectedWidth = self.width; inactiveWidth = 0; selectedOffset = 0
            return
        }
        let others = CGFloat(count - 1)
        let usable = max(0, self.width - others * Self.spacing)
        // Maintain usable icon targets if the rail is constrained by the host (e.g. popover).
        let minimumInactive = min(32, usable / CGFloat(count))
        selectedWidth = min(max(0, preferredSelectionWidth), max(0, usable - others * minimumInactive))
        inactiveWidth = max(0, (usable - selectedWidth) / others)
        selectedOffset = CGFloat(min(max(0, selectedIndex), count - 1)) * (inactiveWidth + Self.spacing)
    }
}
