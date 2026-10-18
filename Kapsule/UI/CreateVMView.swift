// CreateVMView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// The create flow inside a sheet: the OS catalog, then download/configure steps. Shares
/// `OSCatalogView` with the inline first-run surface so both look identical.
struct CreateVMView: View {
    @StateObject private var vm: CreateVMViewModel
    @Environment(\.dismiss) private var dismiss

    init(onCreated: @escaping (VirtualMachineModel, URL?) -> Void) {
        _vm = StateObject(wrappedValue: CreateVMViewModel(onCreated: onCreated))
    }

    var body: some View {
        Group {
            switch vm.step {
            case .chooseSource:
                OSCatalogView(vm: vm) { dismiss() }
            case .downloading(let e):
                DownloadProgressView(downloader: vm.downloader, entry: e) { vm.downloader.cancel() }
            case .configure(let e, _):
                ConfigureVMView(vm: vm, entry: e)
            }
        }
        .frame(width: 780, height: 600)
        .alert("Couldn’t continue",
               isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK", role: .cancel) { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }
}
