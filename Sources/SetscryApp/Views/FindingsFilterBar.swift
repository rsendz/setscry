//
//  FindingsFilterBar.swift
//  Setscry
//
//  Created by Luis Resendez on 01/09/2026.
//

import SwiftUI
import SetscryCore

/// The one sort-and-filter control, shared by every findings list.
///
/// A modifier rather than a toolbar written into each view: six copies of the
/// same two controls would drift apart, and the point of the sidebar is that
/// every section behaves the same way.
private struct FindingsFilter<Item: Sortable>: ViewModifier {
    @Bindable var list: FilteredList<Item>
    let prompt: String

    func body(content: Content) -> some View {
        content
            // `.searchable` rather than a plain field: it puts the box where
            // macOS users look for it and brings ⌘F with it.
            .searchable(text: $list.text, placement: .toolbar, prompt: prompt)
            .toolbar {
                ToolbarItem {
                    Menu {
                        Picker("Sort by", selection: $list.keyID) {
                            ForEach(list.keys) { key in
                                Text(key.title).tag(key.id)
                            }
                        }
                        .pickerStyle(.inline)

                        Divider()

                        Toggle("Reversed", isOn: Binding(
                            get: { !list.isAscending },
                            set: { list.isAscending = !$0 }
                        ))
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .help("Choose how this list is ordered")
                }
            }
    }
}

extension View {
    /// Adds the shared sort menu and filter field for a list.
    func findingsFilter<Item: Sortable>(
        _ list: FilteredList<Item>,
        prompt: String = "Filter by path"
    ) -> some View {
        modifier(FindingsFilter(list: list, prompt: prompt))
    }
}
