// NewVMView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI
import UniformTypeIdentifiers

/// The "New VM" sheet: name, guest type, ISO, CPU, RAM, disk.
struct NewVMView: View {
    let onCreate: (VirtualMachineModel) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = "New Linux VM"
    @State private var guest: VirtualMachineModel.GuestKind = .linux
    @State private var cpuCount = 2
    @State private var memoryGiB = 4
    @State private var diskGiB = 32
    @State private var isoPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Virtual Machine").font(.title2).bold()

            Form {
                TextField("Name", text: $name)
                Picker("Guest OS", selection: $guest) {
                    Text("Linux").tag(VirtualMachineModel.GuestKind.linux)
                    Text("Windows (ARM)").tag(VirtualMachineModel.GuestKind.windowsARM)
                }
                Stepper("CPUs: \(cpuCount)", value: $cpuCount, in: 1...16)
                Stepper("Memory: \(memoryGiB) GB", value: $memoryGiB, in: 1...64)
                Stepper("Disk: \(diskGiB) GB", value: $diskGiB, in: 8...512, step: 8)

                HStack {
                    Text("Install ISO")
                    Spacer()
                    Text(isoPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { chooseISO() }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func create() {
        let model = VirtualMachineModel(
            name: name.trimmingCharacters(in: .whitespaces),
            guest: guest,
            cpuCount: cpuCount,
            memoryMiB: memoryGiB * 1024,
            diskSizeGiB: diskGiB,
            installISOPath: isoPath)
        onCreate(model)
        dismiss()
    }

    private func chooseISO() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let iso = UTType(filenameExtension: "iso") {
            panel.allowedContentTypes = [iso, .diskImage]
        }
        if panel.runModal() == .OK { isoPath = panel.url?.path }
    }
}
