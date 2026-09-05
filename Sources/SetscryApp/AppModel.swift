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

    private let trash: Trashing

    /// The window's undo manager, handed over by `ContentView`.
    ///
    /// `AppModel` is not a view, and the Edit menu's Undo item only reaches the
    /// manager the window vends, so the model borrows that one rather than
    /// owning an unreachable one of its own.
    var undoManager: UndoManager? {
        didSet {
            // Each level holds a whole previous analysis, which on a large
            // folder is not small. Five is more history than anyone reaches for.
            undoManager?.levelsOfUndo = 5
        }
    }

    /// Enough to put one trash operation back.
    private struct TrashedBatch {
        let moves: [(from: URL, to: URL)]
        /// The analysis as it was, kept whole rather than re-derived. Restoring
        /// the exact files restores the exact findings, and re-deriving means
        /// running every pairwise comparison again.
        let analysis: DatasetAnalysis
        let keeperChoices: [DuplicateGroup.ID: URL]
    }

    init(trash: Trashing = SystemTrash()) {
        self.trash = trash
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
    /// document-open request and then never creates the app's window at all:
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
        undoManager?.removeAllActions()
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

        Task {
            if let url = await present(panel) { open(folder: url) }
        }
    }

    /// The window a panel should hang off.
    ///
    /// `AppModel` is not a view, and the Open command comes from the menu bar,
    /// outside the view hierarchy entirely. The key window suits both: a menu
    /// command acts on the window it was pulled down over.
    private var hostWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible)
    }

    /// Runs a panel as a sheet on the window, so the rest of the app stays live
    /// behind it.
    ///
    /// `NSOpenPanel` is an `NSSavePanel`, so one helper covers both. Falls back
    /// to app-modal when there is no window to attach to, which is close to
    /// unreachable but beats the command appearing to do nothing.
    private func present(_ panel: NSSavePanel) async -> URL? {
        guard let window = hostWindow else {
            return panel.runModal() == .OK ? panel.url : nil
        }
        return await panel.beginSheetModal(for: window) == .OK ? panel.url : nil
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
        undoManager?.removeAllActions()
        phase = .idle
    }

    /// Ignores progress that arrives after a scan has already finished or been
    /// cancelled.
    private func report(_ progress: ScanProgress) {
        guard isScanning else { return }
        phase = .scanning(progress)
    }

    // MARK: - About

    /// The standard About panel, filled in by hand.
    ///
    /// Unbundled there is no Info.plist for AppKit to read, so without this the
    /// panel shows the raw executable name and no version at all.
    func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Setscry",
            .applicationVersion: SetscryVersion.display,
            // One number, so suppress the build-number parenthetical rather than
            // printing the same string twice.
            .version: "",
        ])
        NSApp.activate(ignoringOtherApps: true)
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
        // Set lookups for the duplicate kinds rather than a walk over every
        // group comparing whole records: this runs on each render of the detail
        // sheet. Leakage still walks, having no set of its own, which is cheap
        // only because a folder with leakage has few leaked images.
        if analysis.hasExactDuplicates(record) {
            findings.append("Has identical copies elsewhere")
        }
        if analysis.hasNearDuplicates(record) {
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

    /// Whether a report is being written, so the command cannot be run twice
    /// and the window can say something is happening.
    private(set) var isExporting = false

    /// Writes the findings somewhere they can be read without Setscry.
    ///
    /// The format follows the extension the user types, so choosing between a
    /// spreadsheet and a page to send someone is one decision made in the save
    /// panel rather than two menu items.
    func exportReport() {
        guard let analysis, !isExporting else { return }

        let panel = NSSavePanel()
        panel.title = "Export report"
        panel.nameFieldStringValue = "\(analysis.root.lastPathComponent)-report.html"
        panel.allowedContentTypes = [.html, .commaSeparatedText]
        panel.message = "Choose .html for a page to open and share, or .csv for a spreadsheet."

        Task {
            guard let url = await present(panel) else { return }

            isExporting = true
            defer { isExporting = false }

            let keepers = keeperChoices
            // Rendering walks every finding and the write can be large. On the
            // main actor both happen after the panel has gone away, so the
            // window would freeze with nothing on screen to explain it.
            let failure = await Task.detached(priority: .userInitiated) {
                do {
                    let contents = ReportExporter.contents(for: url, analysis: analysis, keepers: keepers)
                    try contents.write(to: url, atomically: true, encoding: .utf8)
                    return String?.none
                } catch {
                    return error.localizedDescription
                }
            }.value

            notice = failure.map { "Couldn't write the report: \($0)" }
                // A silent success reads as a failure. Saying where it went is
                // also how someone finds it again.
                ?? "Exported to \(url.lastPathComponent)."
        }
    }

    /// Moves files to the trash, recoverable by design, since every suggestion
    /// Setscry makes is a suggestion.
    func moveToTrash(_ records: [ImageRecord]) async {
        guard let analysis else { return }

        var moves: [(from: URL, to: URL)] = []
        var failed: [String] = []

        for record in records {
            do {
                moves.append((from: record.url, to: try trash.trash(record.url)))
            } catch {
                failed.append(record.fileName)
            }
        }

        if !moves.isEmpty {
            let removed = Set(moves.map(\.from))
            let previous = TrashedBatch(moves: moves, analysis: analysis, keeperChoices: keeperChoices)

            let updated = await Task.detached(priority: .userInitiated) {
                analysis.removing(removed)
            }.value
            phase = .loaded(updated)
            register(previous)
        }

        notice = failed.isEmpty ? nil : trashFailureNotice(failed)
    }

    /// Offers the batch back through the window's undo manager, which is what
    /// puts a correctly titled item in the Edit menu and binds it to ⌘Z.
    private func register(_ batch: TrashedBatch) {
        // Pluralized by hand: a menu title goes to AppKit as plain text, which
        // prints inflection markup rather than applying it.
        let count = batch.moves.count
        registeringUndo { undoManager in
            undoManager.setActionName("Move \(count) file\(count == 1 ? "" : "s") to the trash")
            undoManager.registerUndo(withTarget: self) { model in
                // `UndoManager` calls back on the thread that registered, which
                // is the main actor in every path that reaches here.
                MainActor.assumeIsolated { model.restore(batch) }
            }
        }
    }

    /// Registers undo work, opening a group first where the manager is not
    /// grouping by event.
    ///
    /// Trashing finishes on a later turn than the click that started it, so a
    /// registration can land outside any event. A manager left to group by
    /// event opens a group for it; one that is not throws instead.
    private func registeringUndo(_ body: (UndoManager) -> Void) {
        guard let undoManager else { return }

        let opensItsOwnGroups = undoManager.groupsByEvent
        if !opensItsOwnGroups { undoManager.beginUndoGrouping() }
        body(undoManager)
        if !opensItsOwnGroups { undoManager.endUndoGrouping() }
    }

    private func restore(_ batch: TrashedBatch) {
        var restored: [(from: URL, to: URL)] = []
        var failed: [String] = []

        for move in batch.moves {
            // A file may have reappeared at the original path since. Moving
            // over it would destroy whatever is there now, so skip it instead.
            guard !FileManager.default.fileExists(atPath: move.from.path) else {
                failed.append(move.from.lastPathComponent)
                continue
            }

            do {
                try trash.restore(move.to, to: move.from)
                restored.append(move)
            } catch {
                failed.append(move.from.lastPathComponent)
            }
        }

        guard !restored.isEmpty else {
            notice = restoreFailureNotice(failed)
            return
        }

        if failed.isEmpty {
            phase = .loaded(batch.analysis)
            keeperChoices = batch.keeperChoices
            notice = nil
        } else {
            // Only on the rare partial failure, and the only way the findings
            // can still describe what is actually on disk.
            phase = .loaded(batch.analysis.removing(Set(batch.moves.map(\.from)).subtracting(restored.map(\.from))))
            keeperChoices = batch.keeperChoices
            notice = restoreFailureNotice(failed)
        }

        // Registering during an undo is how `UndoManager` learns the redo, so
        // the files just put back can be trashed again with ⇧⌘Z.
        let records = restored.compactMap { analysis?.record(for: $0.from) }
        if !records.isEmpty {
            registeringUndo { undoManager in
                undoManager.registerUndo(withTarget: self) { model in
                    MainActor.assumeIsolated {
                        let redo: Task<Void, Never> = Task { await model.moveToTrash(records) }
                        _ = redo
                    }
                }
            }
        }
    }

    private func restoreFailureNotice(_ failed: [String]) -> String {
        let named = failed.prefix(3).joined(separator: ", ")
        let rest = failed.count > 3 ? " and \(failed.count - 3) more" : ""

        return "Couldn't put \(failed.count) file\(failed.count == 1 ? "" : "s") back: \(named)\(rest). "
            + "They may still be in the trash."
    }

    /// Pluralized by hand rather than with inflection markup: `notice` is shown
    /// as a plain string, and the markup would be printed rather than applied.
    private func trashFailureNotice(_ failed: [String]) -> String {
        let named = failed.prefix(3).joined(separator: ", ")
        // Saying how many were left out beats silently dropping them: someone
        // checking that a clean-up finished needs the real count.
        let rest = failed.count > 3 ? " and \(failed.count - 3) more" : ""

        return "Couldn't move \(failed.count) file\(failed.count == 1 ? "" : "s") to the trash: \(named)\(rest)"
    }
}
