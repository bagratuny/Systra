import Foundation

struct RowSelection<ID: Hashable> {
    var items = Set<ID>()
    var anchor: ID?

    mutating func select(_ id: ID, ordered: [ID], extending: Bool, toggling: Bool) {
        if extending, let anchor, let start = ordered.firstIndex(of: anchor), let end = ordered.firstIndex(of: id) {
            let range = Set(ordered[min(start, end)...max(start, end)])
            items = toggling ? items.union(range) : range
        } else if toggling {
            if !items.insert(id).inserted { items.remove(id) }
            anchor = id
        } else {
            items = [id]
            anchor = id
        }
    }
}
