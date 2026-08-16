//
//  HelpView.swift
//  Setscry
//
//  Created by Luis Resendez on 15/08/2026.
//

import SwiftUI

extension Notification.Name {
    /// Posted by the Help menu item. The menu lives outside the view hierarchy,
    /// so it cannot set the sheet's state directly.
    static let showSetscryHelp = Notification.Name("showSetscryHelp")
}

/// What the app is for, in the app.
///
/// Every section already explains itself once it has something to show, but a
/// folder that is in good shape shows empty views, and someone opening Setscry
/// for the first time has no way to tell the difference between "nothing found"
/// and "nothing happened". This is the one place that says what it can find
/// before it has found anything.
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
                Text("Point it at a folder of images and it tells you what's in there.")
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

            step(1, "Open a folder", "Drag one onto the window, or press ⌘O. Every image inside is read once, including images in subfolders.")
            step(2, "Work through the findings", "Start with Exact Duplicates and Won't Open — those are facts, not guesses. Near Duplicates and anything under “With a model” are suggestions worth checking first.")
            step(3, "Remove what you don't want", "Right-click any image to preview it or show it in Finder. Deleting moves files to the Trash, so nothing is gone until you empty it.")
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

            Text("The last three read the images with a model. Setscry uses the one built into macOS by default, so there is nothing to download; CLIP is offered as an upgrade when you want to search by description.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Everything stays on this Mac", systemImage: "lock")
                .font(.headline)
            Text("Images are read on this machine and never uploaded. The only thing Setscry ever downloads is the optional CLIP model, and only if you ask for it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
    }
}

#Preview {
    HelpView()
}
