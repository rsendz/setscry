//
//  AppModel.swift
//  Setscry
//
//  Created by Luis Resendez on 09/08/2026.
//

import AppKit
import Foundation
import Observation
import SetscryCore

/// Owns the app's single piece of state: whichever dataset is open, and what is
/// happening to it.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case idle
        case scanning(ScanProgress)
        case loaded(DatasetAnalysis)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    var selectedSection: DatasetSection = .overview
    /// Non-fatal problems (a file that would not move to Trash, say) surfaced as
    /// a dismissable banner rather than replacing the whole view.
    var notice: String?

    /// The image shown in the detail sheet, and the one handed to Quick Look.
    /// Both live here so any view can open them without threading bindings
    /// through the whole hierarchy.
    var inspecting: ImageRecord?
    var quickLookURL: URL?

    private(set) var recentFolders: [URL]
    private let recents = RecentFolders()

    private var scanTask: Task<Void, Never>?

    init() {
        recentFolders = recents.load()
    }

    var analysis: DatasetAnalysis? {
        if case .loaded(let analysis) = phase { analysis } else { nil }
    }

    var isScanning: Bool {
        if case .scanning = phase { true } else { false }
    }

    // MARK: - Opening

    /// A folder passed on the command line, as in `Setscry --folder ~/datasets/cats`.
    /// Convenient when iterating on the same dataset repeatedly.
    ///
    /// It has to be a flag. AppKit treats a bare positional path as a
    /// document-open request and then never creates the app's window at all.
    /// the process runs, windowless, with no error anywhere.
    static func folderFromLaunchArguments() -> URL? {
        let arguments = Array(CommandLine.arguments.dropFirst())

        var path: String?
        for (index, argument) in arguments.enumerated() {
            if argument == "--folder", index + 1 < arguments.count {
                path = arguments[index + 1]
            } else if argument.hasPrefix("--folder=") {
                path = String(argument.dropFirst("--folder=".count))
            }
        }

        guard let path else { return nil }

        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        return url
    }

    func open(folder: URL) {
        scanTask?.cancel()
        selectedSection = .overview
        notice = nil
        inspecting = nil
        // The choices name files in the folder being replaced, so they mean
        // nothing once a different one is open.
        keeperChoices = [:]
        recentFolders = recents.recording(folder)
        phase = .scanning(ScanProgress(phase: .discovering))

        scanTask = Task { [weak self] in
            let scanner = DatasetScanner()
            let onProgress: @Sendable (ScanProgress) -> Void = { progress in
                Task { @MainActor in self?.report(progress) }
            }

            do {
                // `scan` is nonisolated, so this work runs off the main actor.
                let records = try await scanner.scan(root: folder, onProgress: onProgress)
                let analysis = await Task.detached(priority: .userInitiated) {
                    DatasetAnalysis.make(root: folder, records: records)
                }.value

                guard !Task.isCancelled else { return }
                self?.phase = .loaded(analysis)
            } catch is CancellationError {
                self?.phase = .idle
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Presents the standard folder chooser.
    ///
    /// An `NSOpenPanel` rather than SwiftUI's `fileImporter` because the menu
    /// bar's Open command lives outside the view hierarchy, and this keeps the
    /// menu item and the drop-zone button on one code path.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder of images to scan."

        if panel.runModal() == .OK, let url = panel.url {
            open(folder: url)
        }
    }

    func clearRecentFolders() {
        recents.clear()
        recentFolders = []
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        phase = .idle
    }

    func rescan() {
        guard let root = analysis?.root else { return }
        open(folder: root)
    }

    func close() {
        scanTask?.cancel()
        scanTask = nil
        notice = nil
        keeperChoices = [:]
        phase = .idle
    }

    /// Ignores progress that arrives after a scan has already finished or been
    /// cancelled.
    private func report(_ progress: ScanProgress) {
        guard isScanning else { return }
        phase = .scanning(progress)
    }

    // MARK: - Acting on files

    func revealInFinder(_ record: ImageRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.url])
    }

    func copyPath(_ record: ImageRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.url.path, forType: .string)
        notice = "Copied \(record.fileName) path to the clipboard."
    }

    func quickLook(_ record: ImageRecord) {
        quickLookURL = record.url
    }

    func inspect(_ record: ImageRecord) {
        inspecting = record
    }

    /// Every finding this file takes part in, so the detail view can answer
    /// "why am I looking at this?" without the user retracing their steps.
    func findings(for record: ImageRecord) -> [String] {
        guard let analysis else { return [] }
        var findings: [String] = []

        if let problem = record.problem {
            findings.append(problem.summary)
        }
        if analysis.exactDuplicates.contains(where: { $0.records.contains(record) }) {
            findings.append("Has identical copies elsewhere")
        }
        if analysis.nearDuplicates.contains(where: { $0.records.contains(record) }) {
            findings.append("Looks like a copy of another image")
        }
        if let group = analysis.leakage.first(where: { $0.records.contains(record) }) {
            findings.append("Appears in more than one split (\(group.splitSummary))")
        }

        return findings
    }

    // MARK: - Choosing what to keep

    /// The file the user picked to keep in a duplicate group, where they picked
    /// one. Setscry guesses a keeper, but it is a guess about which copy matters
    /// to someone, so it has to be overridable.
    private(set) var keeperChoices: [DuplicateGroup.ID: URL] = [:]

    func keeper(of group: DuplicateGroup) -> ImageRecord? {
        guard let chosen = keeperChoices[group.id],
              let record = group.records.first(where: { $0.url == chosen })
        else { return group.keeper }
        return record
    }

    func redundant(in group: DuplicateGroup) -> [ImageRecord] {
        guard let keeper = keeper(of: group) else { return [] }
        return group.records.filter { $0 != keeper }
    }

    func chooseKeeper(_ record: ImageRecord, in group: DuplicateGroup) {
        keeperChoices[group.id] = record.url
    }

    // MARK: - Exporting

    /// Writes the findings somewhere they can be read without Setscry.
    ///
    /// The format follows the extension the user types, so choosing between a
    /// spreadsheet and a page to send someone is one decision made in the save
    /// panel rather than two menu items.
    func exportReport() {
        guard let analysis else { return }

        let panel = NSSavePanel()
        panel.title = "Export report"
        panel.nameFieldStringValue = "\(analysis.root.lastPathComponent)-report.html"
        panel.allowedContentTypes = [.html, .commaSeparatedText]
        panel.message = "Choose .html for a page to open and share, or .csv for a spreadsheet."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let isCSV = url.pathExtension.lowercased() == "csv"
        let contents = isCSV
            ? ReportExporter.csv(for: analysis, keepers: keeperChoices)
            : ReportExporter.html(for: analysis, keepers: keeperChoices)

        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            notice = "Couldn't write the report: \(error.localizedDescription)"
        }
    }

    /// Moves files to the trash, recoverable by design, since every suggestion
    /// Setscry makes is a suggestion.
    func moveToTrash(_ records: [ImageRecord]) async {
        guard let analysis else { return }

        var removed: Set<URL> = []
        var failed: [String] = []

        for record in records {
            do {
                try FileManager.default.trashItem(at: record.url, resultingItemURL: nil)
                removed.insert(record.url)
            } catch {
                failed.append(record.fileName)
            }
        }

        if !removed.isEmpty {
            let updated = await Task.detached(priority: .userInitiated) {
                analysis.removing(removed)
            }.value
            phase = .loaded(updated)
        }

        notice = failed.isEmpty
            ? nil
            : "Couldn't move \(failed.count) file(s) to the trash: \(failed.prefix(3).joined(separator: ", "))"
    }
}
