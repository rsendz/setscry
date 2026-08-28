//
//  StatTile.swift
//  Setscry
//
//  Created by Luis Resendez on 11/08/2026.
//

import SwiftUI

/// One honest number, with the sentence that explains what it means.
///
/// Setscry deliberately shows several of these instead of rolling everything into
/// a single invented "quality score".
struct StatTile: View {
    let value: String
    let title: String
    let detail: String
    var systemImage: String
    var isConcerning = false
    /// When set, the tile becomes a button that jumps to the section it
    /// describes. A number worth showing is usually a number worth acting on.
    var destination: DatasetSection?

    @Environment(AppModel.self) private var model

    var body: some View {
        if let destination {
            Button { model.selectedSection = destination } label: { tile }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(destination.title)")
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(isConcerning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))

            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }
}

#Preview {
    StatTile(
        value: "1,284",
        title: "Images",
        detail: "in 6 folders",
        systemImage: "photo.on.rectangle"
    )
    .environment(AppModel())
    .padding()
}
