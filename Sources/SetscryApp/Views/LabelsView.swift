//
//  LabelsView.swift
//  Setscry
//
//  Created by Luis Resendez on 11/08/2026.
//

import Charts
import SwiftUI
import SetscryCore

struct LabelsView: View {
    let health: HealthReport

    var body: some View {
        if !health.hasLabels {
            ContentUnavailableView {
                Label("Nothing to compare here", systemImage: "tag")
            } description: {
                Text("This section counts how many images are in each subfolder — useful when the subfolders are categories, like cats and dogs. The images here aren't sorted into subfolders, so there's nothing to weigh up.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("One bar per subfolder. Names come from the folders, not from the images themselves.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Chart(health.labels) { label in
                        BarMark(
                            x: .value("Images", label.count),
                            y: .value("Label", label.name)
                        )
                        .foregroundStyle(.tint)
                        .annotation(position: .trailing) {
                            Text(label.count.formatted())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxisLabel("Images")
                    .frame(height: max(200, Double(health.labels.count) * 28))

                    if let imbalance = health.labelImbalance, imbalance >= 3 {
                        Label(
                            "The biggest folder holds \(imbalance.formatted(.number.precision(.fractionLength(1))))× as many images as the smallest. If you're training on this, that lopsidedness will show up in the results.",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                    }

                    if health.unlabeledCount > 0 {
                        Text("\(health.unlabeledCount.formatted()) images sit loose in the folder rather than in one of the subfolders.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        }
    }
}
