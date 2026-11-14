// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// The shape of the replies under an opened post, worked out once per
/// context rather than once per row.
///
/// The thread screen used to find each reply's depth in its body: for every
/// row it rebuilt a dictionary of the whole conversation and walked up the
/// parents with a linear search at each step — O(n²) per row, on the main
/// actor, every time the list was evaluated. A five-hundred-reply thread
/// stalled on scroll. Here every reply's parent and depth is found in one
/// pass, and the rows only read them (docs/05 §4).
///
/// The replies are laid out depth first, each under the post it answers,
/// whatever order the server sent them in. Mastodon already sends that order;
/// laying it out here as well means a branch is always one contiguous run of
/// rows, which is what lets a branch fold away behind a single row.
nonisolated struct ThreadLayout: Sendable, Equatable {
    /// Indentation stops here; anything deeper reads as a flat list rather
    /// than a staircase (docs/05 §4).
    static let maxIndent = 5
    /// A branch longer than this shows its first few replies and folds the
    /// rest behind "Show N more replies".
    static let longBranch = 8
    /// How many replies of a long branch show before the fold.
    static let branchPreview = 3

    /// One reply in display order: where it is in `descendants`, how deep it
    /// is below the opened post (1 for a direct reply), and the anchor of
    /// every fold it sits behind, outermost first.
    struct Entry: Sendable, Equatable {
        var index: Int
        var depth: Int
        var foldedBy: [String]

        /// The indentation level drawn: a direct reply sits flush, and the
        /// staircase stops at `maxIndent`.
        var indent: Int { min(max(depth - 1, 0), ThreadLayout.maxIndent) }
    }

    /// What the list draws: a reply, or the row a fold collapses into.
    enum Row: Sendable, Equatable, Identifiable {
        case reply(index: Int, indent: Int, depth: Int)
        case more(anchorID: String, count: Int, indent: Int)

        var id: String {
            switch self {
            case .reply(let index, _, _): "reply-\(index)"
            case .more(let anchorID, _, _): "more-\(anchorID)"
            }
        }
    }

    private(set) var entries: [Entry] = []
    /// Each reply's depth below the opened post, by id.
    private(set) var depths: [String: Int] = [:]
    /// How many replies each fold hides, and the indent its row is drawn at.
    private(set) var folds: [String: (count: Int, indent: Int)] = [:]
    /// How many replies the layout was built from, so a list that changed
    /// under it is noticed rather than indexed out of range.
    private(set) var count = 0

    init() {}

    init(focusedID: String, descendants: [Status]) {
        count = descendants.count
        guard !descendants.isEmpty else { return }

        var indexByID: [String: Int] = [:]
        for (index, status) in descendants.enumerated() where indexByID[status.id] == nil {
            indexByID[status.id] = index
        }

        // Children in the order the server sent them. A reply whose parent is
        // not among the replies — the opened post itself, or one a filter
        // left out — starts a branch of its own at the top.
        var children: [Int: [Int]] = [:]
        var roots: [Int] = []
        for (index, status) in descendants.enumerated() where indexByID[status.id] == index {
            if let parent = status.inReplyToID, parent != focusedID,
                let parentIndex = indexByID[parent], parentIndex != index
            {
                children[parentIndex, default: []].append(index)
            } else {
                roots.append(index)
            }
        }

        // Depth first, iteratively: a reply chain thousands deep must not
        // overflow the stack. Each reply remembers which reply it was laid
        // out under, so subtree sizes follow the tree actually drawn.
        var visited = Set<Int>()
        var order: [(index: Int, depth: Int)] = []
        var drawnParent: [Int: Int] = [:]
        order.reserveCapacity(descendants.count)
        func walk(from starts: [Int]) {
            var stack: [(index: Int, depth: Int, parent: Int?)] =
                starts.reversed().map { ($0, 1, nil) }
            while let (index, depth, parent) = stack.popLast() {
                // A cycle in what the server sent (a post replying to its own
                // reply) is broken at the second visit.
                guard visited.insert(index).inserted else { continue }
                order.append((index, depth))
                if let parent { drawnParent[index] = parent }
                for child in (children[index] ?? []).reversed() {
                    stack.append((child, depth + 1, index))
                }
            }
        }
        walk(from: roots)
        // Replies only reachable through a cycle still show, each starting a
        // branch, rather than vanishing from the conversation.
        let stranded = descendants.indices.filter {
            indexByID[descendants[$0].id] == $0 && !visited.contains($0)
        }
        for index in stranded where !visited.contains(index) { walk(from: [index]) }

        // Subtree sizes, so a fold knows how many it hides without counting
        // again. Every reply comes after its parent in `order`, so walking it
        // backwards adds each subtree into its parent exactly once.
        var subtree = [Int](repeating: 1, count: descendants.count)
        for (index, _) in order.reversed() {
            if let parent = drawnParent[index] { subtree[parent] += subtree[index] }
        }

        // Folds. A reply at the deepest indent folds away everything below
        // it; a top-level branch longer than `longBranch` shows its first
        // `branchPreview` replies and folds the rest. Both hide a contiguous
        // run of the depth-first order, so a fold is a start and a length.
        var activeFolds: [(anchor: String, end: Int)] = []
        var position = 0
        var branchStart: (anchor: String, position: Int, size: Int)?
        for (index, depth) in order {
            activeFolds.removeAll { $0.end <= position }
            let status = descendants[index]

            if depth == 1 {
                let size = subtree[index] - 1
                branchStart = size > Self.longBranch ? (status.id, position, size) : nil
            }
            if let branch = branchStart, position == branch.position + Self.branchPreview + 1 {
                let hidden = branch.size - Self.branchPreview
                let key = "branch-\(branch.anchor)"
                folds[key] = (hidden, 1)
                activeFolds.append((key, position + hidden))
            }

            entries.append(
                Entry(index: index, depth: depth, foldedBy: activeFolds.map(\.anchor)))
            depths[status.id] = depth

            if depth - 1 == Self.maxIndent, subtree[index] > 1 {
                let hidden = subtree[index] - 1
                let key = "deep-\(status.id)"
                folds[key] = (hidden, Self.maxIndent)
                activeFolds.append((key, position + 1 + hidden))
            }
            position += 1
        }
    }

    static func == (lhs: ThreadLayout, rhs: ThreadLayout) -> Bool {
        lhs.entries == rhs.entries && lhs.count == rhs.count
    }

    /// The rows to draw with these folds opened. Linear in the number of
    /// replies, and only the cheap part: everything it reads was worked out
    /// when the layout was built.
    func rows(expanded: Set<String>) -> [Row] {
        var rows: [Row] = []
        rows.reserveCapacity(entries.count)
        var announced = Set<String>()
        for entry in entries {
            // The outermost closed fold is the one that shows; one inside it
            // is announced only once that one opens.
            if let closed = entry.foldedBy.first(where: { !expanded.contains($0) }) {
                if announced.insert(closed).inserted, let fold = folds[closed] {
                    rows.append(.more(anchorID: closed, count: fold.count, indent: fold.indent))
                }
                continue
            }
            rows.append(.reply(index: entry.index, indent: entry.indent, depth: entry.depth))
        }
        return rows
    }
}
