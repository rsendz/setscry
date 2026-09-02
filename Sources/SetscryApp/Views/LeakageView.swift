//
//  LeakageView.swift
//  Setscry
//
//  Created by Luis Resendez on 11/08/2026.
//

import SwiftUI
import SetscryCore

struct LeakageView: View {
    let groups: [LeakageGroup]

    @Environment(AppModel.self) private var model
    @State private var list: FilteredList<LeakageGroup>

    init(groups: [LeakageGroup]) {
        self.groups = groups
        _list = State(initialValue: FilteredList(groups, keys: LeakageGroup.sortKeys))
    }

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                "No leakage found",
                systemImage: "checkmark.circle",
                description: Text("No image is in more than one of the train, validation and test folders.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("These images are in more than one of the train, validation and test folders, so a model gets tested on pictures it already studied. Identical files are certain; the rest are worth checking.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(list.items) { group in
                        card(for: group)
                    }
                }
                .padding(20)
            }
            .findingsFilter(list)
            .onChange(of: groups) { list.source = $1 }
            .overlay {
                if list.items.isEmpty {
                    ContentUnavailableView.search(text: list.text)
                }
            }
        }
    }

    private func card(for group: LeakageGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.splitSummary)
                    .font(.headline)
                Spacer()
                Text(confidence(for: group))
                    .font(.caption)
                    .foregroundStyle(group.containsIdenticalFiles ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(group.recordsBySplit, id: \.split) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.split.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(alignment: .top, spacing: 10) {
                                ForEach(entry.records) { record in
                                    copyView(record)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }

    private func copyView(_ record: ImageRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(record: record, side: 110)
                .imageActions(for: record)

            Text(record.relativePath)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)

            Button("Reveal in Finder", systemImage: "folder") { model.revealInFinder(record) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .frame(width: 130, alignment: .leading)
    }

    private func confidence(for group: LeakageGroup) -> String {
        group.containsIdenticalFiles
            ? "Identical file in both splits"
            : "Similar to within \(group.spread) of 64 bits"
    }
}

#Preview("Nothing leaked") {
    LeakageView(groups: [])
        .environment(AppModel())
        .frame(width: 760, height: 520)
}
