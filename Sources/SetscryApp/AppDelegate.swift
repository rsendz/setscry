//
//  AppDelegate.swift
//  Setscry
//
//  Created by Luis Resendez on 09/08/2026.
//

import AppKit

/// Running from a SwiftPM executable rather than an `.app` bundle means macOS
/// treats the process as a background tool: the window opens behind everything
/// and never takes focus. Promoting the activation policy on launch gives the
/// same behavior as a bundled app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
