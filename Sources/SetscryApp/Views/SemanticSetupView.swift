//
//  SemanticSetupView.swift
//  Setscry
//
//  Created by Luis Resendez on 12/08/2026.
//

import SwiftUI
import SetscryCore
import SetscryMLX

/// The gate in front of everything that needs the model: states the download
/// size and where the work runs before anything is fetched.
struct SemanticSetupView: View {
    let analysis: DatasetAnalysis
    let title: String
    let explanation: String

    @Environment(SemanticModel.self) private var semantic

    var body: some View {
        phaseContent
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch semantic.phase {
        case .idle:
            ContentUnavailableView {
                Label(title, systemImage: "sparkle.magnifyingglass")
            } description: {
                VStack(spacing: 10) {
                    Text(explanation)
                    Text(semantic.modelDescription)
                        .font(.callout)
                    Text(semantic.deviceDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            } actions: {
                VStack(spacing: 12) {
                    Button("Read the Images") { semantic.build(for: analysis) }
                        .buttonStyle(.borderedProminent)

                    upgradeOffer
                }
            }

        case .preparing:
            progressView(
                title: "Getting the model ready",
                detail: semantic.isModelReady ? "Loading the model" : "Starting download",
                fraction: nil
            )

        case .downloading(let progress):
            progressView(
                title: "Downloading \(semantic.modelName)",
                detail: byteDetail(for: progress),
                fraction: progress.fractionCompleted
            )

        case .embedding(let completed, let total):
            progressView(
                title: "Reading images with the model",
                detail: embeddingDetail(completed: completed, total: total),
                fraction: total > 0 ? Double(completed) / Double(total) : nil
            )

        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't set that up", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { semantic.build(for: analysis) }
            }

        case .ready:
            EmptyView()
        }
    }

    /// The one place CLIP is offered. It stays an offer rather than a
    /// requirement: everything here works with the built-in model, and the
    /// download only buys searching by description.
    @ViewBuilder
    private var upgradeOffer: some View {
        switch semantic.backend {
        case .builtIn where semantic.isCLIPSupported:
            VStack(spacing: 4) {
                Button("Use CLIP Instead") { semantic.use(.clip) }
                    .buttonStyle(.link)
                Text("Downloads 606 MB once. Adds searching by description, and sharper groups.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .clip:
            VStack(spacing: 4) {
                Button("Use the Built-in Model Instead") { semantic.use(.builtIn) }
                    .buttonStyle(.link)
                Text("Nothing to download, but no searching by description.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        default:
            // The built-in model still works here; only CLIP is out of reach,
            // so this explains the absence rather than blocking the view.
            Text(semantic.unsupportedReason)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    private func progressView(title: String, detail: String, fraction: Double?) -> some View {
        VStack(spacing: 14) {
            if let fraction {
                ProgressView(title, value: fraction)
            } else {
                ProgressView(title)
            }

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text(semantic.deviceDescription)
                .font(.footnote)
                .foregroundStyle(.tertiary)

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
        return "\(progress) · \(semantic.reusedCount.formatted()) already read earlier"
    }

    private func byteDetail(for progress: CLIPModelStore.Progress) -> String {
        guard progress.bytesExpected > 0 else {
            return progress.bytesReceived.formatted(.byteCount(style: .file))
        }
        return "\(progress.bytesReceived.formatted(.byteCount(style: .file))) of \(progress.bytesExpected.formatted(.byteCount(style: .file)))"
    }
}
