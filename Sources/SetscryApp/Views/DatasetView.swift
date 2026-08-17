//
//  DatasetView.swift
//  Setscry
//
//  Created by Luis Resendez on 11/08/2026.
//

import SwiftUI
import SetscryCore

/// The loaded-dataset shell: sections on the left, one focused view on the right.
struct DatasetView: View {
    let analysis: DatasetAnalysis

    @Environment(AppModel.self) private var model
    @State private var isShowingHelp = false

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            // `id: \.self` makes the row identity and the selection binding the
            // same type; relying on `Identifiable` plus a `tag` lets the two
            // disagree, and the sidebar then opens on the wrong section.
            List(selection: $model.selectedSection) {
                Section("Findings") {
                    ForEach(DatasetSection.deterministicCases, id: \.self) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .badge(section.badge(for: analysis) ?? 0)
                            .help(section.summary)
                    }
                }

                // Separated because everything below is the model's opinion
                // rather than a fact about the files.
                Section("With a model") {
                    ForEach(DatasetSection.modelCases, id: \.self) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .help(section.summary)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            detail
                .navigationTitle(model.selectedSection.title)
                .navigationSubtitle(analysis.root.lastPathComponent)
                .toolbar { toolbarContent }
        }
        .safeAreaInset(edge: .top) { noticeBanner }
        .sheet(isPresented: $isShowingHelp) { HelpView() }
        .onReceive(NotificationCenter.default.publisher(for: .showSetscryHelp)) { _ in
            isShowingHelp = true
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .overview:
            OverviewView(analysis: analysis)
        case .exactDuplicates:
            DuplicatesView(
                groups: analysis.exactDuplicates,
                explanation: "These files are byte-for-byte identical. Keeping one of each would free \(analysis.health.reclaimableBytes.formatted(.byteCount(style: .file)))."
            )
        case .nearDuplicates:
            DuplicatesView(
                groups: analysis.nearDuplicates,
                explanation: "These look like the same image resized, re-compressed or lightly edited. Worth a second look before removing anything."
            )
        case .problems:
            ProblemImagesView(records: analysis.problemImages)
        case .labels:
            LabelsView(health: analysis.health)
        case .leakage:
            LeakageView(groups: analysis.leakage)
        case .search:
            SearchView(analysis: analysis)
        case .clusters:
            ClustersView(analysis: analysis)
        case .labelCheck:
            LabelCheckView(analysis: analysis)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button("What can Setscry do?", systemImage: "questionmark.circle") {
                isShowingHelp = true
            }
            Button("Rescan", systemImage: "arrow.clockwise") { model.rescan() }
            Button("Close Dataset", systemImage: "xmark.circle") { model.close() }
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = model.notice {
            HStack(spacing: 8) {
                Label(notice, systemImage: "exclamationmark.circle")
                    .font(.callout)
                Spacer()
                Button("Dismiss") { model.notice = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.yellow.opacity(0.18))
        }
    }
}
