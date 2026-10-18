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
                Section("Name") {
                    TextField("Name", text: $vm.name)
                        .accessibilityLabel("Virtual machine name")
                    Picker("Operating system", selection: $vm.guest) {
                        Text("Linux").tag(VirtualMachineModel.GuestKind.linux)
                        Text("Windows (ARM)").tag(VirtualMachineModel.GuestKind.windowsARM)
                    }
                }

                Section {
                    settingRow(
                        title: "Processors",
                        value: "\(vm.cpuCount)",
                        hint: "How many CPU cores this machine can use.") {
                        Stepper("", value: $vm.cpuCount, in: 1...16).labelsHidden()
                    }
                    settingRow(
                        title: "Memory",
                        value: "\(vm.memoryGiB) GB",
                        hint: "RAM given to this machine while it runs.") {
                        Stepper("", value: $vm.memoryGiB, in: 1...64).labelsHidden()
                    }
                    settingRow(
                        title: "Disk size",
                        value: "\(vm.diskGiB) GB",
                        hint: "Storage for the machine. It only uses space as it fills up.") {
                        Stepper("", value: $vm.diskGiB, in: 8...512, step: 8).labelsHidden()
                    }
                } header: {
                    Text("Power")
                } footer: {
                    Text("These can be changed later. The defaults suit most work.")
                }

                Section {
                    HStack {
                        Text(vm.customLocation?.path ?? "Kapsule’s default folder")
                            .foregroundStyle(vm.customLocation == nil ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if vm.customLocation != nil {
                            Button("Use Default") { vm.customLocation = nil }
                        }
                        Button("Choose…") { vm.chooseInstallLocation() }
                            .accessibilityLabel("Choose where to save this machine")
                    }
                } header: {
                    Text("Where to save it")
                } footer: {
                    Text("The machine and its \(vm.diskGiB) GB of storage live here. Choose an external drive to keep space free on your Mac.")
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

    /// A labeled setting: a title and plain-language hint on the left, the current value
    /// and its control on the right. The whole row reads as one item to VoiceOver.
    @ViewBuilder
    private func settingRow<Control: View>(
        title: String, value: String, hint: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            control()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint(hint)
    }
}
