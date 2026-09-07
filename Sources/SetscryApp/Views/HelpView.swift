//
//  HelpView.swift
//  Setscry
//
//  Created by Luis Resendez on 15/08/2026.
//

import SwiftUI
import SetscryCore

extension Notification.Name {
    /// Posted by the Help menu item. The menu lives outside the view hierarchy,
    /// so it cannot set the sheet's state directly.
    static let showSetscryHelp = Notification.Name("showSetscryHelp")
}

/// What the app is for, in the app.
///
/// Every section explains itself once it has something to show, but a folder in
/// good shape shows empty views, and someone opening Setscry for the first time
/// cannot tell "nothing found" from "nothing happened". This says what it looks
/// for before it has found anything.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    steps
                    sections
                    privacy
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 620)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How Setscry works")
                    .font(.title2.weight(.semibold))
                Text("Point it at a folder of images and it tells you what is in there.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleaning up a folder")
                .font(.headline)

            step(1, "Open a folder", "Drag one onto the window, or press ⌘O. Every image inside is read once, subfolders included.")
            step(2, "Work through the findings", "Exact duplicates and Won't open are facts. Near duplicates and anything under “With a model” are suggestions, so check those first.")
            step(3, "Remove what you don't want", "In a duplicate group, pick the one to keep, then trash the rest. Deleting moves files to the trash, so nothing is gone until you empty it.")
            step(4, "Keep findings current", "The open folder is watched, including its subfolders. File ▸ Watch folder for changes pauses updates; ⌘R refreshes manually. External changes clear undo history so an old snapshot cannot replace newer findings.")
            step(5, "Or take them elsewhere", "Drag any image out to Finder or another app. Hold Command as you drop to move it instead of copying it.")
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(width: 24, height: 24)
                .background(.tint.opacity(0.15), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What each section shows")
                .font(.headline)

            ForEach(DatasetSection.allCases) { section in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: section.systemImage)
                        .foregroundStyle(.tint)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title).font(.callout.weight(.medium))
                        Text(section.summary).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

        }
    }

    /// The note about CLIP lives here rather than under the section list. On its
    /// own it was an orphan line with a section gap above and below it, and it
    /// says the same thing this block does.
    private var privacy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Everything stays on this Mac", systemImage: "lock")
                .font(.headline)
            Text("Images are read here and never uploaded. The last three sections use CLIP, a model that ships inside the app, so there is nothing to download either.")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Where someone looks before reporting something.
            Text("Setscry \(SetscryVersion.display)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
    }
}

#Preview {
    HelpView()
}
