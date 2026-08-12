//
//  DuplicatesView.swift
//  Setscry
//
//  Created by Luis Resendez on 11/08/2026.
//

import SwiftUI
import SetscryCore

struct DuplicatesView: View {
    let groups: [DuplicateGroup]
    let explanation: String

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                "Nothing to review",
                systemImage: "checkmark.circle",
                description: Text("Setscry didn't find any duplicates of this kind.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(groups) { group in
                        DuplicateGroupCard(group: group)
                    }
                }
                .padding(20)
            }
        }
    }
}
