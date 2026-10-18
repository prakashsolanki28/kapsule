// CreateVMView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// The "Create New" screen: install from an image, grab Windows from Microsoft, or pick a
/// free system to download. Modeled on a professional first-run assistant.
struct CreateVMView: View {
    @StateObject private var vm: CreateVMViewModel
    @Environment(\.dismiss) private var dismiss

    init(onCreated: @escaping (VirtualMachineModel, URL?, Bool) -> Void) {
        _vm = StateObject(wrappedValue: CreateVMViewModel(onCreated: onCreated))
    }

    var body: some View {
        Group {
            switch vm.step {
            case .chooseSource:          sourcePicker
            case .downloading(let e):    DownloadProgressView(downloader: vm.downloader, entry: e) { vm.downloader.cancel() }
            case .configure(let e, _):   ConfigureVMView(vm: vm, entry: e)
            case .importing(let name):   ImportProgressView(name: name, fraction: vm.importFraction)
            }
        }
        .frame(width: 720, height: 560)
        .alert("Couldn’t continue",
               isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK", role: .cancel) { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }

    private var sourcePicker: some View {
        VStack(spacing: 0) {
            Text("Create New").font(.system(size: 34, weight: .semibold)).padding(.top, 28)
            Divider().padding(.horizontal, 60).padding(.top, 12)

            HStack(spacing: 60) {
                windowsTile
                imageFileTile
            }
            .frame(maxHeight: .infinity)

            freeSystems
        }
    }

    private var windowsTile: some View {
        BigTile(symbol: "window.casement", tint: .blue,
                title: "Get Windows 11\nfrom Microsoft") {
            if let win = vm.catalog.first(where: { $0.guest == .windowsARM }) {
                vm.select(win)
            }
        }
    }

    private var imageFileTile: some View {
        BigTile(symbol: "opticaldiscdrive", tint: .secondary,
                title: "Install Windows,\nLinux, or macOS\nfrom an image file") {
            vm.chooseImageFile()
        }
    }

    private var freeSystems: some View {
        VStack(spacing: 10) {
            Text("Free Systems").font(.title3.weight(.semibold))
            HStack(spacing: 28) {
                ForEach(vm.catalog.filter { $0.guest != .windowsARM }) { entry in
                    FreeSystemButton(entry: entry) { vm.select(entry) }
                }
            }
            HStack {
                Button("Open…") { vm.chooseImageFile() }
                Button("Open VM or Disk…") { vm.openForImport() }
                    .help("Import a .pvm, .utm, or disk image (qcow2, vmdk, img…)")
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.4))
    }
}

private struct BigTile: View {
    let symbol: String
    let tint: Color
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 80))
                    .foregroundStyle(tint)
                Text(title)
                    .multilineTextAlignment(.center)
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .frame(width: 220, height: 240)
            .background(hover ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct ImportProgressView: View {
    let name: String
    let fraction: Double

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.doc").font(.system(size: 56))
            Text("Importing \(name)").font(.title2.weight(.semibold))
            ProgressView(value: fraction).frame(width: 360)
            Text("Converting disk to Kapsule’s format… \(Int(fraction * 100))%")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Text("Large disks can take a few minutes. The original is left untouched.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FreeSystemButton: View {
    let entry: OSCatalogEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: entry.symbolName).font(.system(size: 34))
                Text(entry.kind == .download ? "Download\n\(entry.name)" : entry.name)
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(width: 120)
            }
        }
        .buttonStyle(.plain)
        .help(entry.subtitle)
    }
}
