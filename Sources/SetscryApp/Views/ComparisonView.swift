import SwiftUI
import SetscryCore

struct ComparisonView: View {
    @Environment(AppModel.self) private var model
    @State private var kind: FolderComparison.Kind = .exact
    @State private var filter = ""

    private var comparison: ComparisonModel { model.comparison }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(comparison.folder?.lastPathComponent ?? "Is this already in my library?")
                        .font(.title3.weight(.semibold))
                    Text("Compare another folder with the open library. Both folders stay untouched.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose folder…") { model.chooseComparisonFolder() }
            }
            if let message = comparison.message {
                Label(message, systemImage: "info.circle").font(.callout)
            }
            if comparison.isRunning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Reading and comparing images…")
                    Text("\(comparison.progress.processed) files read").foregroundStyle(.secondary)
                    Button("Cancel") { comparison.clear() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if comparison.hasResults {
                results
            } else {
                ContentUnavailableView("Compare two folders", systemImage: "rectangle.on.rectangle",
                    description: Text("Exact matches are byte-identical. Possible copies share visual structure and colour. Review those before deciding what to keep."))
            }
        }
        .padding(20)
    }

    private var results: some View {
        VStack(spacing: 12) {
            Picker("Show", selection: $kind) {
                ForEach(FolderComparison.Kind.allCases, id: \.self) { category in
                    Text("\(category.rawValue) (\(comparison.entries.count { $0.kind == category }))")
                        .tag(category)
                }
            }
            .pickerStyle(.segmented)
            TextField("Filter incoming paths", text: $filter)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Filter incoming paths")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(comparison.entries.filter {
                        $0.kind == kind && (filter.isEmpty || $0.candidate.relativePath.localizedStandardContains(filter))
                    }) { entry in
                        row(entry)
                    }
                }
            }
            .overlay {
                if !comparison.entries.contains(where: {
                    $0.kind == kind && (filter.isEmpty || $0.candidate.relativePath.localizedStandardContains(filter))
                }) {
                    ContentUnavailableView("No images in this category", systemImage: "photo")
                }
            }
            Text("A snapshot of both folders at comparison time. Choose the folder again after changing incoming files.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ entry: FolderComparison.Entry) -> some View {
        HStack(alignment: .top, spacing: 20) {
            image(entry.candidate, caption: "Incoming")
            if !entry.matches.isEmpty {
                Image(systemName: "arrow.right").padding(.top, 36).accessibilityHidden(true)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(entry.matches) { image($0, caption: "In library") }
                    }
                }
            } else {
                Text(entry.kind == .unreadable
                     ? "This file could not be compared reliably."
                     : "No exact or visual match in the library.")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 36)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
    }

    private func image(_ record: ImageRecord, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(.caption).foregroundStyle(.secondary)
            Button { model.quickLook(record) } label: {
                ThumbnailView(record: record, side: 100)
            }
            .buttonStyle(.plain)
            .help("Quick Look \(record.fileName)")
            Text(record.relativePath).font(.caption).lineLimit(2).truncationMode(.middle)
        }
        .frame(width: 140, alignment: .leading)
        .contextMenu {
            Button("Quick Look") { model.quickLook(record) }
            Button("Reveal in Finder") { model.revealInFinder(record) }
            Button("Copy path") { model.copyPath(record) }
        }
    }
}
