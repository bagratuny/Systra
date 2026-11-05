import Foundation

@main struct TabRailChecks {
    static func main() {
        for count in [7, 8] {
            for width: CGFloat in [398, 440, 472, 520] {
                for preferred: CGFloat in [74, 106, 148] {
                    for selected in 0..<count {
                        let layout = TabRailGeometry(width: width, count: count, selectedIndex: selected, preferredSelectionWidth: preferred)
                        precondition(layout.width == width)
                        precondition(layout.inactiveWidth >= 32 && layout.selectedWidth >= 44)
                        precondition(layout.selectedOffset >= 0 && layout.selectedOffset + layout.selectedWidth <= width + 0.001)
                        // Buttons exactly fill the stable rail; no dead space at its edges.
                        let filled = layout.selectedWidth + CGFloat(count - 1) * (layout.inactiveWidth + TabRailGeometry.spacing)
                        precondition(abs(filled - width) < 0.001)
                        if selected == 0 { precondition(layout.selectedOffset == 0) }
                        if selected == count - 1 { precondition(abs(layout.selectedOffset + layout.selectedWidth - width) < 0.001) }
                    }
                }
            }
        }
        let short = TabRailGeometry(width: 472, count: 8, selectedIndex: 3, preferredSelectionWidth: 74)
        let long = TabRailGeometry(width: 472, count: 8, selectedIndex: 3, preferredSelectionWidth: 148)
        precondition(short.width == long.width && short.selectedWidth < long.selectedWidth)
        let constrained = TabRailGeometry(width: 260, count: 8, selectedIndex: 7, preferredSelectionWidth: 200)
        precondition(constrained.selectedOffset + constrained.selectedWidth <= 260.001)
        print("PASS: fixed tab rail, title-sized selection, complete hit areas, first/last alignment and constrained layouts")
    }
}
