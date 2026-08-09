//
//  SetscryApp.swift
//  Setscry
//
//  Created by Luis Resendez on 09/08/2026.
//

import SwiftUI

@main
struct SetscryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Owned here rather than in `ContentView` so the menu bar can reach them.
    @State private var model = AppModel()
    @State private var semantic = SemanticModel()

    var body: some Scene {
        WindowGroup("Setscry") {
            ContentView()
                .environment(model)
                .environment(semantic)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            AppCommands(model: model, semantic: semantic)
        }
    }
}
