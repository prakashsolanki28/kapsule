// ConfigureVMView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// Final step of the create flow: name, resources, and the install location.
struct ConfigureVMView: View {
    @ObservedObject var vm: CreateVMViewModel
    let entry: OSCatalogEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: entry?.symbolName ?? "opticaldiscdrive").font(.system(size: 36))
                VStack(alignment: .leading) {
                    Text("Configure Virtual Machine").font(.title2.weight(.semibold))
                    if let path = vm.isoPath {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
            }
            .padding(20)
            Divider()

            Form {
                Section("General") {
                    TextField("Name", text: $vm.name)
                    Picker("Guest OS", selection: $vm.guest) {
                        Text("Linux").tag(VirtualMachineModel.GuestKind.linux)
                        Text("Windows (ARM)").tag(VirtualMachineModel.GuestKind.windowsARM)
                    }
                }
                Section("Resources") {
                    Stepper("Processors: \(vm.cpuCount)", value: $vm.cpuCount, in: 1...16)
                    Stepper("Memory: \(vm.memoryGiB) GB", value: $vm.memoryGiB, in: 1...64)
                    Stepper("Disk size: \(vm.diskGiB) GB", value: $vm.diskGiB, in: 8...512, step: 8)
                }
                Section("Install Location") {
                    HStack {
                        Text(vm.customLocation?.path ?? "Default — Kapsule library")
                            .foregroundStyle(vm.customLocation == nil ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if vm.customLocation != nil {
                            Button("Use Default") { vm.customLocation = nil }
                        }
                        Button("Choose…") { vm.chooseInstallLocation() }
                    }
                    Text("The VM and its \(vm.diskGiB) GB disk are stored here. Pick an external drive to save space on your Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Back") { vm.resetToCatalog() }
                Spacer()
                Button("Create") { vm.createVM() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!vm.canCreate)
            }
            .padding(20)
        }
    }
}
