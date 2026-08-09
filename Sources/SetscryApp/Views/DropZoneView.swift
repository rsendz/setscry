//
//  DropZoneView.swift
//  Setscry
//
//  Created by Luis Resendez on 09/08/2026.
//

import SwiftUI

struct DropZoneView: View {
    let onChooseFolder: () -> Void
    let onDropFolder: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Drop a folder of images")
                    .font(.title2.weight(.semibold))
                Text("Setscry reads them on this Mac. Nothing is uploaded.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Button("Choose Folder…", action: onChooseFolder)
                .controlSize(.large)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .padding(24)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: \.hasDirectoryPath) ?? urls.first else { return false }
            onDropFolder(folder)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

#Preview {
    DropZoneView(onChooseFolder: {}, onDropFolder: { _ in })
        .frame(width: 760, height: 520)
}
