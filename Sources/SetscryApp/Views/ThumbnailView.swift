//
//  ThumbnailView.swift
//  Setscry
//
//  Created by Luis Resendez on 12/08/2026.
//

import SwiftUI
import SetscryCore

struct ThumbnailView: View {
    let record: ImageRecord
    var side: CGFloat = 96

    @State private var image: CGImage?

    var body: some View {
        content
            .frame(width: side, height: side)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            .clipShape(.rect(cornerRadius: 8))
            .task(id: record.url) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(image, scale: 1, label: Text(record.fileName))
                .resizable()
                .scaledToFill()
        } else if record.problem != nil {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(record.fileName), could not be displayed")
        } else {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Loading \(record.fileName)")
        }
    }

    private func load() async {
        // Decode at 2× so the thumbnail stays sharp on Retina displays.
        image = await ThumbnailLoader.shared
            .thumbnail(for: record.url, maxPixelSize: Int(side * 2))?
            .cgImage
    }
}
