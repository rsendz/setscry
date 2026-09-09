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
                // The open folder, which used to be the detail view's subtitle.
                // It belongs over the sidebar: it names what the whole list is
                // about, and it is not a section you can select.
                Label(analysis.root.lastPathComponent, systemImage: "folder")
                    .font(.headline)
                    .padding(.vertical, 2)
                    .help(analysis.root.path)
                    .selectionDisabled()

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
            // Title only, no subtitle. A two-line title puts its first line
            // above the toolbar buttons, which reads as misaligned however
            // carefully the block as a whole is centred. The folder name lives
            // over the sidebar instead, where it belongs anyway.
            detail
                .navigationTitle(model.selectedSection.title)
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
        case .allImages:
            AllImagesView(records: analysis.records)
        case .exactDuplicates:
            DuplicatesView(
                groups: analysis.exactDuplicates,
                kind: .exact,
                explanation: "Byte-for-byte identical. Keeping one of each frees \(analysis.health.reclaimableBytes.formatted(.byteCount(style: .file)))."
            )
        case .nearDuplicates:
            DuplicatesView(
                groups: analysis.nearDuplicates,
                kind: .near,
                explanation: "The same image resized, re-compressed or lightly edited. Worth a look before removing anything."
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
        case .comparison:
            ComparisonView()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if model.isRefreshing {
                ProgressView().controlSize(.small).help("Updating findings")
            }
            Button("Help", systemImage: "questionmark.circle") {
                isShowingHelp = true
            }
            Button("Rescan", systemImage: "arrow.clockwise") { model.rescan() }
            Button("Close folder", systemImage: "xmark.circle") { model.close() }
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
