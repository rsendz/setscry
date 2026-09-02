//
//  FilteredList.swift
//  Setscry
//
//  Created by Luis Resendez on 01/09/2026.
//

import Foundation
import Observation
import SetscryCore

/// The criteria one findings list is using, and the list they produce.
///
/// Holding the result rather than deriving it in `body` is the whole point.
/// SwiftUI re-evaluates a view's body constantly, so a filter and a sort written
/// as computed properties become a full pass over the folder per frame, and a
/// stutter per keystroke once the folder is large.
@Observable
@MainActor
final class FilteredList<Item: Sortable> {
    var text = "" { didSet { if text != oldValue { schedule() } } }
    var keyID: String { didSet { if keyID != oldValue { reapply() } } }
    var isAscending = true { didSet { if isAscending != oldValue { reapply() } } }

    /// The unfiltered input. Views assign to this when the analysis changes.
    var source: [Item] { didSet { reapply() } }

    private(set) var items: [Item]

    let keys: [SortKey<Item>]
    private var work: Task<Void, Never>?

    init(_ source: [Item], keys: [SortKey<Item>]) {
        self.source = source
        self.keys = keys
        self.keyID = keys.first?.id ?? ""
        self.items = Sorting.apply(source, text: "", key: keys.first, isAscending: true)
    }

    private var key: SortKey<Item>? { keys.first { $0.id == keyID } ?? keys.first }

    /// Debounced, because this runs on every keystroke.
    private func schedule() {
        work?.cancel()
        work = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await apply()
        }
    }

    /// Picking a different key is one deliberate action rather than a stream of
    /// them, so it does not want the debounce.
    private func reapply() {
        work?.cancel()
        work = Task { await apply() }
    }

    /// The work without the debounce, so tests do not race the timer.
    func apply() async {
        let source = source
        let text = text
        let key = key
        let isAscending = isAscending

        let result = await Task.detached(priority: .userInitiated) {
            Sorting.apply(source, text: text, key: key, isAscending: isAscending)
        }.value

        guard !Task.isCancelled else { return }
        items = result
    }
}
