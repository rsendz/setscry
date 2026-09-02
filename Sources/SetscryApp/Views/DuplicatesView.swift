//
//  DuplicatesView.swift
//  Setscry
//
//  Created by Luis Resendez on 11/08/2026.
//

import SwiftUI
import SetscryCore

struct DuplicatesView: View {
    let groups: [DuplicateGroup]
    let explanation: String

    @Environment(AppModel.self) private var model
    @State private var isConfirmingTrash = false
    @State private var list: FilteredList<DuplicateGroup>

    /// `kind` only to choose the sort keys: an exact group has no similarity to
    /// order by, so offering that key there would promise an order it has not got.
    init(groups: [DuplicateGroup], kind: DuplicateGroup.Kind, explanation: String) {
        self.groups = groups
        self.explanation = explanation
        _list = State(initialValue: FilteredList(groups, keys: DuplicateGroup.sortKeys(for: kind)))
    }

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                "Nothing to review",
                systemImage: "checkmark.circle",
                description: Text("No duplicates of this kind.")
            )
        } else {
            // Walked once and threaded through rather than recomputed wherever
            // it is needed: `body` re-runs on every keeper change, and this
            // visits every copy in every group in the folder.
            content(
                shown: list.items,
                redundant: list.items.flatMap { model.redundant(in: $0) }
            )
        }
    }

    private func content(shown: [DuplicateGroup], redundant: [ImageRecord]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(shown) { group in
                    DuplicateGroupCard(group: group)
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) { actionBar(shown: shown, redundant: redundant) }
        .findingsFilter(list)
        .onChange(of: groups) { list.source = $1 }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView.search(text: list.text)
            }
        }
        .confirmationDialog(
            "Move \(redundant.count) file\(redundant.count == 1 ? "" : "s") to the trash?",
            isPresented: $isConfirmingTrash,
            titleVisibility: .visible
        ) {
            Button("Move to trash", role: .destructive) {
                Task { await model.moveToTrash(redundant) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("One image stays in each group, the one marked Keeping. You can put the rest back from the trash.")
        }
    }

    private func actionBar(shown: [DuplicateGroup], redundant: [ImageRecord]) -> some View {
        let reclaimable = redundant.reduce(0) { $0 + $1.byteSize }

        return HStack {
            Text("^[\(shown.count) group](inflect: true) · ")
                + Text(reclaimable.formatted(.byteCount(style: .file)) + " recoverable")
            Spacer()

            Button("Keep one of each, trash the rest") { isConfirmingTrash = true }
                .buttonStyle(.borderedProminent)
                .disabled(redundant.isEmpty)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, 16)
        // More below than above, so the row does not sit against the window edge.
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(.bar)
    }
}
