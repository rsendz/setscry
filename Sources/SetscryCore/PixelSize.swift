//
//  PixelSize.swift
//  Setscry
//
//  Created by Luis Resendez on 01/08/2026.
//

import Foundation

/// The pixel dimensions of a decoded image.
public struct PixelSize: Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var pixelCount: Int { width * height }

    public var displayString: String { "\(width) × \(height)" }
}
