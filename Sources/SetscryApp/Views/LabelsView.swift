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
                Label("No labels found", systemImage: "tag")
            } description: {
                Text("Setscry reads labels from folder names, expecting something like root/class-name/image.jpg. This folder doesn't have that shape, so there's nothing to compare.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Labels come from folder names, not from the images themselves.")
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
                            "The largest class has \(imbalance.formatted(.number.precision(.fractionLength(1))))× the images of the smallest. That's worth knowing before you train on it.",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                    }

                    if health.unlabeledCount > 0 {
                        Text("\(health.unlabeledCount.formatted()) images sit outside any label folder.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        }
    }
}
