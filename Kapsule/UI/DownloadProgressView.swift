// DownloadProgressView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// Shows download + verification progress for a catalog OS image.
struct DownloadProgressView: View {
    @ObservedObject var downloader: ImageDownloader
    let entry: OSCatalogEntry
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: entry.symbolName).font(.system(size: 56))
            Text("Downloading \(entry.name)").font(.title2.weight(.semibold))

            switch downloader.phase {
            case .downloading(let frac, let got, let total):
                ProgressView(value: frac).frame(width: 360)
                Text("\(byteString(got)) of \(total > 0 ? byteString(total) : "…")  (\(Int(frac * 100))%)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            case .verifying:
                ProgressView().controlSize(.small)
                Text("Verifying checksum…").font(.callout).foregroundStyle(.secondary)
            case .finished:
                Label("Download complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).multilineTextAlignment(.center)
            case .idle:
                ProgressView().controlSize(.small)
            }

            Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
            Button("Cancel", role: .cancel, action: onCancel)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
