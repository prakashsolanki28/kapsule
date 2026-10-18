// CreateVMView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// The "Create New" screen: a small store of open-source operating systems. Each OS wears
/// its own brand color so the catalog reads like a shelf of real distributions. Pick one
/// to download, or install from your own ISO.
struct CreateVMView: View {
    @StateObject private var vm: CreateVMViewModel
    @Environment(\.dismiss) private var dismiss

    init(onCreated: @escaping (VirtualMachineModel, URL?) -> Void) {
        _vm = StateObject(wrappedValue: CreateVMViewModel(onCreated: onCreated))
    }

    var body: some View {
        Group {
            switch vm.step {
            case .chooseSource:          catalog
            case .downloading(let e):    DownloadProgressView(downloader: vm.downloader, entry: e) { vm.downloader.cancel() }
            case .configure(let e, _):   ConfigureVMView(vm: vm, entry: e)
            }
        }
        .frame(width: 760, height: 580)
        .alert("Couldn’t continue",
               isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK", role: .cancel) { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }

    // MARK: Catalog

    private let columns = [GridItem(.adaptive(minimum: 340, maximum: 420), spacing: 16)]

    private var catalog: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(vm.catalog) { entry in
                        OSCard(entry: entry) { vm.select(entry) }
                    }
                }
                .padding(20)
            }
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Virtual Machine").font(.system(size: 26, weight: .semibold))
                Text("Choose an operating system to install.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                vm.chooseImageFile()
            } label: {
                Label("Install from ISO…", systemImage: "opticaldiscdrive")
            }
            .controlSize(.large)
            .help("Install from an ISO file you already have")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack {
            Text("Images are downloaded from each project and verified when a checksum is published.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.3))
    }
}

/// A single operating-system card: brand badge, name, what it is, and an action.
private struct OSCard: View {
    let entry: OSCatalogEntry
    let action: () -> Void
    @State private var hover = false

    private var accent: Color { Color(hex: entry.accentHex) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                badge
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.headline)
                    Text(entry.tagline)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.subtitle)
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                actionLabel
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(hover ? 0.18 : 0), radius: 8, y: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(hover ? accent.opacity(0.6) : Color.primary.opacity(0.08),
                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    /// A rounded square washed in the distro's accent, with its glyph.
    private var badge: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(colors: [accent, accent.opacity(0.78)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 54, height: 54)
            .overlay(
                Image(systemName: entry.symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white))
    }

    /// "Download" for images Kapsule fetches; "Get" (opens the project) otherwise.
    @ViewBuilder private var actionLabel: some View {
        let title = entry.isDownloadable ? "Download" : "Get"
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(hover ? Color.white : accent)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(
                Capsule().fill(hover ? accent : accent.opacity(0.14)))
    }
}
