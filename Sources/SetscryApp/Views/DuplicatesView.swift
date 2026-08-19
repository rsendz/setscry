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

    /// Every copy except the one kept in each group — the whole point of the
    /// view, expressed as one action instead of one click per group.
    private var redundant: [ImageRecord] {
        groups.flatMap(\.redundant)
    }

    private var reclaimable: Int64 {
        groups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                "Nothing to review",
                systemImage: "checkmark.circle",
                description: Text("Setscry didn't find any duplicates of this kind.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(groups) { group in
                        DuplicateGroupCard(group: group)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .confirmationDialog(
                "Move ^[\(redundant.count) file](inflect: true) to the Trash?",
                isPresented: $isConfirmingTrash,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    Task { await model.moveToTrash(redundant) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("One image from each of the \(groups.count) groups is kept — the one marked Keep. Everything else goes to the Trash, so you can put it back.")
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Text("^[\(groups.count) group](inflect: true) · \(reclaimable.formatted(.byteCount(style: .file))) recoverable")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Button("Keep One of Each, Trash the Rest") { isConfirmingTrash = true }
                .buttonStyle(.borderedProminent)
                .disabled(redundant.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
