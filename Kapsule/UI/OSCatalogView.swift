// OSCatalogView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// The operating-system catalog: a shelf of open-source systems, each in its own brand
/// color. Rendered inline as the first-run surface (when no VM exists) and inside the
/// create sheet. Picking a system starts its download or opens its project page; the
/// toolbar offers installing from a local ISO.
struct OSCatalogView: View {
    @ObservedObject var vm: CreateVMViewModel
    /// Shown inline (no chrome) vs. in a sheet (with a Cancel affordance).
    var onCancel: (() -> Void)?

    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 18)]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(vm.catalog) { entry in
                        OSCard(entry: entry) { vm.select(entry) }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Create New")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.4)
                Text("Choose an operating system to install, or use your own ISO.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(action: vm.chooseImageFile) {
                Label("Install from ISO…", systemImage: "opticaldiscdrive")
            }
            .controlSize(.large)
            .help("Install from an ISO file you already have")
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Images download from each project and are verified against a published checksum.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let onCancel {
                Button("Cancel", action: onCancel)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.28))
        .overlay(Divider(), alignment: .top)
    }
}

/// A single operating-system card: brand badge, name, what it is, and an action.
struct OSCard: View {
    let entry: OSCatalogEntry
    let action: () -> Void
    @State private var hover = false

    private var accent: Color { Color(hex: entry.accentHex) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                badge
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(entry.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.7))
                        .lineLimit(1)
                        .padding(.top, 1)
                }
                Spacer(minLength: 8)
                actionLabel
            }
            .padding(16)
            .frame(height: 104, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        hover ? accent.opacity(0.65) : Color.primary.opacity(0.08),
                        lineWidth: 1))
            .shadow(color: .black.opacity(hover ? 0.22 : 0.08),
                    radius: hover ? 14 : 5, y: hover ? 6 : 2)
            .scaleEffect(hover ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hover)
    }

    /// A rounded square washed in the distro's accent, carrying its glyph.
    private var badge: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(
                LinearGradient(colors: [accent, accent.opacity(0.74)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: entry.symbolName)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white))
            .shadow(color: accent.opacity(hover ? 0.5 : 0.25),
                    radius: hover ? 10 : 5, y: 3)
    }

    /// "Download" for images Kapsule fetches; "Get" (opens the project) otherwise.
    @ViewBuilder private var actionLabel: some View {
        Text(entry.isDownloadable ? "Download" : "Get")
            .font(.callout.weight(.semibold))
            .foregroundStyle(hover ? .white : accent)
            .padding(.horizontal, 15)
            .padding(.vertical, 6)
            .background(Capsule().fill(hover ? accent : accent.opacity(0.14)))
    }
}
