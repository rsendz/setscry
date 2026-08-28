//
//  ContentView.swift
//  Setscry
//
//  Created by Luis Resendez on 09/08/2026.
//

import QuickLook
import SwiftUI
import SetscryCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(SemanticModel.self) private var semantic

    var body: some View {
        @Bindable var model = model

        Group {
            switch model.phase {
            case .idle:
                DropZoneView(onChooseFolder: model.chooseFolder, onDropFolder: model.open)

            case .scanning(let progress):
                ScanningView(progress: progress, onCancel: model.cancelScan)

            case .loaded(let analysis):
                if analysis.records.isEmpty {
                    ContentUnavailableView {
                        Label("No images in that folder", systemImage: "photo.on.rectangle")
                    } description: {
                        Text("\(analysis.root.lastPathComponent) has no files Setscry can read. It looks for JPEG, PNG, HEIC, TIFF, GIF, BMP and WebP.")
                    } actions: {
                        Button("Choose another folder") { model.chooseFolder() }
                    }
                } else {
                    DatasetView(analysis: analysis)
                }

            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't scan that folder", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Choose another folder") { model.chooseFolder() }
                }
            }
        }
        // Embeddings belong to one folder; opening another must not carry the
        // previous index over. Files removed within a folder need no reset,
        // the views look records up by URL and skip what is gone.
        .onChange(of: model.analysis?.root) { semantic.reset() }
        .task {
            if let folder = AppModel.folderFromLaunchArguments() {
                model.open(folder: folder)
            }
        }
        .sheet(item: $model.inspecting) { record in
            ImageDetailView(record: record)
        }
        .quickLookPreview($model.quickLookURL)
    }
}
