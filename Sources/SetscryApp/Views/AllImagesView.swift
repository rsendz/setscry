//
//  AllImagesView.swift
//  Setscry
//
//  Created by Luis Resendez on 02/09/2026.
//

import SwiftUI
import SetscryCore

/// Every image in the folder, findings or not.
///
/// Without this the app can only show what is wrong: a folder with nothing wrong
/// with it is nine empty states and no way to look at your own pictures.
struct AllImagesView: View {
    let records: [ImageRecord]

    @State private var list: FilteredList<ImageRecord>

    init(records: [ImageRecord]) {
        self.records = records
        _list = State(initialValue: FilteredList(records, keys: ImageRecord.sortKeys))
    }

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 12)]

    /// Fixed rather than self-sizing. A tile that sizes to its content makes
    /// SwiftUI measure candidates while working out the scroll height, and at a
    /// hundred thousand files that stops being lazy.
    private let tileWidth: CGFloat = 132
    private let tileHeight: CGFloat = 176

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(list.items) { record in
                    tile(record)
                }
            }
            .padding(20)
        }
        .findingsFilter(list)
        .onChange(of: records) { list.source = $1 }
        .safeAreaInset(edge: .bottom) { actionBar }
        .overlay {
            if list.items.isEmpty {
                ContentUnavailableView.search(text: list.text)
            }
        }
    }

    private func tile(_ record: ImageRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(record: record, side: tileWidth)
                .imageActions(for: record)

            Text(record.relativePath)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)

            Text(caption(for: record))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(width: tileWidth, height: tileHeight, alignment: .topLeading)
    }

    private func caption(for record: ImageRecord) -> String {
        let size = record.byteSize.formatted(.byteCount(style: .file))
        guard let pixels = record.pixelSize else { return size }
        return "\(pixels.width)×\(pixels.height) · \(size)"
    }

    private var actionBar: some View {
        HStack {
            // Two separate Texts, not a ternary: a conditional produces a String,
            // and the inflection markup would then be printed rather than applied.
            Group {
                if list.items.count == records.count {
                    Text("^[\(records.count) image](inflect: true)")
                } else {
                    Text("^[\(list.items.count) image](inflect: true) of \(records.count)")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            Spacer()
        }
        .padding(.horizontal, 16)
        // More below than above, so the row does not sit against the window edge.
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(.bar)
    }
}

#Preview("No images") {
    AllImagesView(records: [])
        .environment(AppModel())
        .frame(width: 760, height: 520)
}
