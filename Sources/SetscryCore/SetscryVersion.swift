//
//  SetscryVersion.swift
//  Setscry
//
//  Created by Luis Resendez on 29/08/2026.
//

import Foundation

/// The one place Setscry's version is written.
///
/// A Swift constant rather than the bundle's `CFBundleShortVersionString`:
/// there is no Info.plist at all under `swift run`, so a version that lived
/// only in the bundle could not be shown or exported from a development build.
/// `Scripts/version.sh` reads this file, and `Scripts/make-app.sh` stamps the
/// plist from it, so the binary and the bundle cannot disagree.
public enum SetscryVersion {
    /// Read by Scripts/version.sh, so this stays a plain literal on one line.
    public static let current = "1.5"

    /// Whether this process is running from an `.app` rather than `swift run`.
    public static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    /// What the app shows. An unbundled build says so: "1.5" from a working
    /// copy and "1.5" from a release are not the same software.
    public static var display: String { isBundled ? current : "\(current) (dev)" }
}
