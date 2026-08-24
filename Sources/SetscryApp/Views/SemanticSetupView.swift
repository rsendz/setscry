//
//  SemanticSetupView.swift
//  Setscry
//
//  Created by Luis Resendez on 12/08/2026.
//

import SwiftUI
import SetscryCore
import SetscryMLX

/// The gate in front of the sections that need the model: what they do, and one
/// button to start.
struct SemanticSetupView: View {
    let analysis: DatasetAnalysis
    let title: String
    let explanation: String

    @Environment(SemanticModel.self) private var semantic

    var body: some View {
        if !semantic.isSupported {
            ContentUnavailableView {
                Label("Not available in this build", systemImage: "cpu")
            } description: {
                Text(semantic.unsupportedReason)
            }
        } else {
            phaseContent
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch semantic.phase {
        case .idle:
            ContentUnavailableView {
                Label(title, systemImage: "sparkle.magnifyingglass")
            } description: {
                VStack(spacing: 8) {
                    Text(explanation)
                    Text(semantic.deviceDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            } actions: {
                Button("Read the images") { semantic.build(for: analysis) }
                    .buttonStyle(.borderedProminent)
            }

        case .preparing:
            progressView(title: "Loading the model", detail: "", fraction: nil)

        // Only a source build reaches this: a packaged app carries the weights.
        case .downloading(let progress):
            progressView(
                title: "Fetching the model",
                detail: byteDetail(for: progress),
                fraction: progress.fractionCompleted
            )

        case .embedding(let completed, let total):
            progressView(
                title: "Reading images",
                detail: embeddingDetail(completed: completed, total: total),
                fraction: total > 0 ? Double(completed) / Double(total) : nil
            )

        case .failed(let message):
            ContentUnavailableView {
                Label("That didn't work", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { semantic.build(for: analysis) }
            }

        case .ready:
            EmptyView()
        }
    }

    private func progressView(title: String, detail: String, fraction: Double?) -> some View {
        VStack(spacing: 14) {
            if let fraction {
                ProgressView(title, value: fraction)
            } else {
                ProgressView(title)
            }

            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button("Cancel") { semantic.cancel() }
                .padding(.top, 4)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func embeddingDetail(completed: Int, total: Int) -> String {
        let progress = "\(completed.formatted()) of \(total.formatted())"
        guard semantic.reusedCount > 0 else { return progress }
        return "\(progress), \(semantic.reusedCount.formatted()) reused from earlier"
    }

    private func byteDetail(for progress: CLIPModelStore.Progress) -> String {
        guard progress.bytesExpected > 0 else {
            return progress.bytesReceived.formatted(.byteCount(style: .file))
        }
        return "\(progress.bytesReceived.formatted(.byteCount(style: .file))) of \(progress.bytesExpected.formatted(.byteCount(style: .file)))"
    }
}
