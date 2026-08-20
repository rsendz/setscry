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
    @State private var isShowingHelp = false

    var body: some View {
        VStack(spacing: 22) {
            OpeningArtwork()

            VStack(spacing: 6) {
                Text("Drop a folder of images")
                    .font(.title2.weight(.semibold))
                Text("Setscry reads them on this Mac. Nothing is uploaded.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button("Choose Folder…", action: onChooseFolder)
                    .controlSize(.large)

                Button("What can Setscry do?") { isShowingHelp = true }
                    .buttonStyle(.borderless)
            }
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
        .sheet(isPresented: $isShowingHelp) { HelpView() }
        .onReceive(NotificationCenter.default.publisher(for: .showSetscryHelp)) { _ in
            isShowingHelp = true
        }
    }
}

/// A row of image tiles that settle into place, with a slow light sweeping
/// across them.
///
/// Decorative only — it takes no clicks and says nothing the text below doesn't.
/// It exists because the first screen is otherwise a static icon and a dashed
/// rectangle, and this shows what the app is about to do to a pile of images.
private struct OpeningArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAppeared = false
    @State private var sweep = false

    private let tiles = 5

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<tiles, id: \.self) { index in
                tile(index)
            }
        }
        .frame(height: 76)
        .overlay { if !reduceMotion { shine } }
        .mask { tileRow }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(duration: 0.7, bounce: 0.35)) { hasAppeared = true }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false).delay(0.8)) {
                sweep = true
            }
        }
    }

    private func tile(_ index: Int) -> some View {
        let settled = reduceMotion || hasAppeared
        // Fanned slightly outward from the middle, the way a handful of prints
        // dropped on a table would land.
        let lean = Double(index - tiles / 2) * 2.5

        return RoundedRectangle(cornerRadius: 8)
            .fill(gradient(index))
            .frame(width: 52, height: 66)
            .rotationEffect(.degrees(settled ? lean : 0))
            .scaleEffect(settled ? 1 : 0.86)
            .offset(y: settled ? 0 : 14)
            .opacity(settled ? 1 : 0)
            .animation(
                .spring(duration: 0.7, bounce: 0.35).delay(Double(index) * 0.08),
                value: hasAppeared
            )
    }

    /// The tiles again, as a mask, so the sweep is clipped to them instead of
    /// crossing the empty space between.
    private var tileRow: some View {
        HStack(spacing: 10) {
            ForEach(0..<tiles, id: \.self) { index in
                RoundedRectangle(cornerRadius: 8)
                    .frame(width: 52, height: 66)
                    .rotationEffect(.degrees(Double(index - tiles / 2) * 2.5))
            }
        }
        .frame(height: 76)
    }

    private var shine: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.35), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 90)
        .offset(x: sweep ? 240 : -240)
        .blendMode(.plusLighter)
    }

    private func gradient(_ index: Int) -> LinearGradient {
        let hue = 0.55 + Double(index) * 0.045
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.45, brightness: 0.85),
                Color(hue: hue + 0.06, saturation: 0.55, brightness: 0.6),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    DropZoneView(onChooseFolder: {}, onDropFolder: { _ in })
        .frame(width: 760, height: 520)
}
