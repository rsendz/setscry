//
//  ScanningView.swift
//  Setscry
//
//  Created by Luis Resendez on 09/08/2026.
//

import SwiftUI
import SetscryCore

struct ScanningView: View {
    let progress: ScanProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            progressIndicator
                .frame(maxWidth: 360)

            Text(statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if let file = progress.currentFile {
                Text(file)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
            }

            Button("Cancel", action: onCancel)
                .padding(.top, 8)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var progressIndicator: some View {
        if let fraction = progress.fractionCompleted {
            ProgressView(progress.phase.displayName, value: fraction)
        } else {
            ProgressView(progress.phase.displayName)
                .progressViewStyle(.linear)
        }
    }

    private var statusLine: String {
        switch progress.phase {
        case .discovering:
            progress.processed > 0
                ? "\(progress.processed.formatted()) images found so far"
                : "Looking through the folder…"
        case .reading:
            "\(progress.processed.formatted()) of \(progress.total.formatted()) images"
        case .analyzing:
            "Comparing \(progress.total.formatted()) images"
        }
    }
}

#Preview {
    ScanningView(
        progress: ScanProgress(
            phase: .reading,
            processed: 128,
            total: 400,
            currentFile: "IMG_0421.HEIC"
        ),
        onCancel: {}
    )
    .frame(width: 760, height: 520)
}
