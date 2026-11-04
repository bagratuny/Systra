import Foundation

@main struct SelectionChecks {
    static func main() {
        var selection = RowSelection<Int>()
        let order = [1, 2, 3, 4, 5]
        selection.select(2, ordered: order, extending: false, toggling: false)
        precondition(selection.items == [2])
        selection.select(4, ordered: order, extending: false, toggling: true)
        precondition(selection.items == [2, 4])
        selection.select(2, ordered: order, extending: false, toggling: true)
        precondition(selection.items == [4])
        selection.select(5, ordered: order, extending: true, toggling: false)
        precondition(selection.items == [2, 3, 4, 5])
        selection.select(1, ordered: order, extending: true, toggling: true)
        precondition(selection.items == Set(order))
        selection.select(3, ordered: order, extending: false, toggling: false)
        precondition(selection.items == [3])
        print("Selection checks: PASS")
    }
}
