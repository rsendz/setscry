//
//  ReportExporter.swift
//  Setscry
//
//  Created by Luis Resendez on 18/08/2026.
//

import Foundation

/// Turns an analysis into something that outlives the window it was shown in.
///
/// Two shapes, because the two audiences want different things: CSV for
/// filtering a long list of findings somewhere else, HTML for handing someone
/// the summary without asking them to install anything. Both are produced from
/// the analysis alone, with no UI types involved, so both are testable.
public enum ReportExporter {
    /// One row per finding, in the order the sections appear in the app.
    ///
    /// A finding is a file plus the reason it was flagged, so a file caught by
    /// two checks appears twice. That is what makes the file filterable by
    /// reason without having to parse a combined column.
    /// `keepers` names the file the user chose to keep in a group, where they
    /// chose one, so the report says the same thing the window does.
    public static func csv(
        for analysis: DatasetAnalysis,
        keepers: [DuplicateGroup.ID: URL] = [:]
    ) -> String {
        var rows = ["finding,file,group,detail"]

        for record in analysis.problemImages {
            rows.append(row("Won't open", record.relativePath, "", record.problem?.summary ?? ""))
        }

        for (index, group) in analysis.exactDuplicates.enumerated() {
            for record in group.records {
                let role = record == keeper(of: group, keepers) ? "keeping" : "redundant copy"
                rows.append(row("Exact duplicate", record.relativePath, "exact-\(index + 1)", role))
            }
        }

        for (index, group) in analysis.nearDuplicates.enumerated() {
            for record in group.records {
                let role = record == keeper(of: group, keepers) ? "keeping" : "similar copy"
                let detail = group.spread.map { "\(role), differs by \($0) of 64 bits" } ?? role
                rows.append(row("Near duplicate", record.relativePath, "near-\(index + 1)", detail))
            }
        }

        for (index, group) in analysis.leakage.enumerated() {
            for record in group.records {
                let certainty = group.containsIdenticalFiles ? "identical copy" : "similar copy"
                rows.append(row(
                    "Split leakage", record.relativePath, "leak-\(index + 1)",
                    "\(group.splitSummary), \(certainty)"
                ))
            }
        }

        return rows.joined(separator: "\n") + "\n"
    }

    /// A single self-contained page: no stylesheet, no script, no images, so it
    /// survives being emailed around.
    public static func html(
        for analysis: DatasetAnalysis,
        keepers: [DuplicateGroup.ID: URL] = [:]
    ) -> String {
        let health = analysis.health
        let folder = escape(analysis.root.lastPathComponent)
        let scanned = analysis.scannedAt.formatted(date: .abbreviated, time: .shortened)

        var body = """
        <h1>\(folder)</h1>
        <p class="sub">\(health.totalImages.formatted()) images · \
        \(health.totalBytes.formatted(.byteCount(style: .file))) · scanned \(escape(scanned))</p>
        """

        body += statTiles(health)

        body += section(
            "Won't open",
            "Files that could not be decoded.",
            rows: analysis.problemImages.map { [$0.relativePath, $0.problem?.summary ?? ""] },
            headers: ["File", "Problem"]
        )

        body += duplicateSection(
            "Exact duplicates",
            "Byte-identical files. \(health.reclaimableBytes.formatted(.byteCount(style: .file))) recoverable by keeping one of each.",
            groups: analysis.exactDuplicates,
            keepers: keepers
        )

        body += duplicateSection(
            "Near duplicates",
            "The same picture resized, re-saved or lightly edited. Suggestions, not certainties.",
            groups: analysis.nearDuplicates,
            keepers: keepers
        )

        body += section(
            "Split leakage",
            "Images appearing in more than one of train, validation and test.",
            rows: analysis.leakage.map { group in
                [
                    group.records.map { escape($0.relativePath) }.joined(separator: "<br>"),
                    escape(group.splitSummary),
                    group.containsIdenticalFiles ? "Identical files" : "Similar, worth checking",
                ]
            },
            headers: ["Files", "Splits", "Certainty"],
            escapesCells: false
        )

        if health.hasLabels {
            body += section(
                "Folder balance",
                "How many images sit in each subfolder.",
                rows: health.labels.map { [$0.name, $0.count.formatted()] },
                headers: ["Folder", "Images"]
            )
        }

        return page(title: folder, body: body)
    }

    // MARK: - CSV helpers

    private static func row(_ fields: String...) -> String {
        fields.map(field).joined(separator: ",")
    }

    /// Quotes only when it has to, and doubles embedded quotes: the whole of
    /// RFC 4180 that matters for paths, which routinely contain commas.
    private static func field(_ value: String) -> String {
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - HTML helpers

    private static func statTiles(_ health: HealthReport) -> String {
        let tiles: [(String, String)] = [
            ("Images", health.totalImages.formatted()),
            ("Won't open", health.problemCount.formatted()),
            ("Exact duplicate groups", health.exactDuplicateGroups.formatted()),
            ("Recoverable", health.reclaimableBytes.formatted(.byteCount(style: .file))),
            ("Near duplicate groups", health.nearDuplicateGroups.formatted()),
            ("Leaked images", health.leakageCount.formatted()),
        ]

        let cells = tiles.map { label, value in
            "<div class=\"tile\"><span class=\"value\">\(escape(value))</span>\(escape(label))</div>"
        }
        return "<div class=\"tiles\">" + cells.joined() + "</div>"
    }

    /// The file to keep in a group: the user's pick if they made one, otherwise
    /// the one Setscry suggests.
    private static func keeper(of group: DuplicateGroup, _ keepers: [DuplicateGroup.ID: URL]) -> ImageRecord? {
        guard let chosen = keepers[group.id],
              let record = group.records.first(where: { $0.url == chosen })
        else { return group.keeper }
        return record
    }

    private static func duplicateSection(
        _ title: String,
        _ blurb: String,
        groups: [DuplicateGroup],
        keepers: [DuplicateGroup.ID: URL]
    ) -> String {
        section(
            title,
            blurb,
            rows: groups.enumerated().map { index, group in
                [
                    "\(index + 1)",
                    group.records.map { record in
                        let path = escape(record.relativePath)
                        return record == keeper(of: group, keepers) ? "<strong>\(path)</strong> (keeping)" : path
                    }.joined(separator: "<br>"),
                    redundantBytes(of: group, keepers).formatted(.byteCount(style: .file)),
                ]
            },
            headers: ["Group", "Files", "Recoverable"],
            escapesCells: false
        )
    }

    private static func redundantBytes(of group: DuplicateGroup, _ keepers: [DuplicateGroup.ID: URL]) -> Int64 {
        let kept = keeper(of: group, keepers)
        return group.records.filter { $0 != kept }.reduce(0) { $0 + $1.byteSize }
    }

    /// Pass `escapesCells: false` only for rows whose cells are already escaped
    /// markup, the ones listing several files that need `<br>` between them.
    private static func section(
        _ title: String,
        _ blurb: String,
        rows: [[String]],
        headers: [String],
        escapesCells: Bool = true
    ) -> String {
        guard !rows.isEmpty else {
            return "<h2>\(escape(title))</h2><p class=\"none\">Nothing found.</p>"
        }

        let head = headers.map { "<th>\(escape($0))</th>" }.joined()
        let body = rows.map { cells in
            "<tr>" + cells.map { "<td>\(escapesCells ? escape($0) : $0)</td>" }.joined() + "</tr>"
        }.joined()

        return """
        <h2>\(escape(title))</h2>
        <p class="blurb">\(escape(blurb))</p>
        <table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table>
        """
    }

    private static func page(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Setscry: \(title)</title>
        <style>
        :root { color-scheme: light dark; }
        body { font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
               margin: 0 auto; padding: 40px 24px; max-width: 900px; }
        h1 { margin: 0 0 4px; font-size: 28px; }
        h2 { margin: 40px 0 4px; font-size: 19px; }
        .sub, .blurb, .none { color: #888; margin: 0 0 12px; }
        .tiles { display: flex; flex-wrap: wrap; gap: 12px; margin: 24px 0 8px; }
        .tile { flex: 1 1 140px; padding: 12px 14px; border-radius: 10px;
                background: rgba(128,128,128,0.12); font-size: 13px; color: #888; }
        .tile .value { display: block; font-size: 22px; font-weight: 600; color: inherit;
                       color: CanvasText; margin-bottom: 2px; }
        table { border-collapse: collapse; width: 100%; font-size: 14px; }
        th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid rgba(128,128,128,0.25);
                 vertical-align: top; }
        th { font-weight: 600; color: #888; font-size: 12px; text-transform: uppercase;
             letter-spacing: 0.04em; }
        footer { margin-top: 48px; color: #888; font-size: 13px; }
        </style>
        </head>
        <body>
        \(body)
        <footer>Generated by Setscry. Everything here was read on the machine that made this file.</footer>
        </body>
        </html>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
