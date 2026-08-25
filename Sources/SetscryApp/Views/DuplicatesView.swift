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

    /// Every copy except the one kept in each group, so a cleaning pass is one
    /// confirmation rather than one per group.
    private var redundant: [ImageRecord] {
        groups.flatMap { model.redundant(in: $0) }
    }

    private var reclaimable: Int64 {
        redundant.reduce(0) { $0 + $1.byteSize }
    }

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                "Nothing to review",
                systemImage: "checkmark.circle",
                description: Text("No duplicates of this kind.")
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
    }

    private var actionBar: some View {
        HStack {
            Text("^[\(groups.count) group](inflect: true) · ")
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
        .padding(.vertical, 10)
        .background(.bar)
    }
}
