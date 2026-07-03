import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var viewModel: RemoteViewModel
    @StateObject private var discovery = TVDiscovery()
    @Environment(\.dismiss) private var dismiss
    @State private var showManualAdd = false
    @State private var resolvingID: String?

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.tvs.isEmpty {
                    Section("My TVs") {
                        ForEach(viewModel.tvs) { tv in
                            NavigationLink {
                                TVDetailView(tv: tv)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(tv.name)
                                            if tv.clientKey == nil {
                                                Text("NOT PAIRED")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(.orange.opacity(0.25)))
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        Text(tv.host)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if tv.id == viewModel.selectedTV?.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    viewModel.removeTV(tv)
                                }
                            }
                        }
                    }
                }

                Section {
                    let newTVs = discovery.found.filter { found in
                        !viewModel.tvs.contains { $0.name == found.name }
                    }
                    if newTVs.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking for TVs on your network…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(newTVs) { found in
                            Button {
                                add(found)
                            } label: {
                                HStack {
                                    Label(found.name, systemImage: "tv")
                                    Spacer()
                                    if resolvingID == found.id {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .disabled(resolvingID != nil)
                        }
                    }
                } header: {
                    Text("Found on your network")
                } footer: {
                    Text("Your TV must be on and connected to the same Wi‑Fi network. When you add a TV, accept the pairing prompt that appears on its screen.")
                }

                Section {
                    Button {
                        showManualAdd = true
                    } label: {
                        Label("Add TV by IP Address", systemImage: "keyboard")
                    }
                }
            }
            .navigationTitle("TVs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showManualAdd) {
                ManualAddView()
            }
        }
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    private func add(_ found: TVDiscovery.FoundTV) {
        resolvingID = found.id
        Task {
            let host = await TVDiscovery.resolveHost(for: found.endpoint)
            resolvingID = nil
            if let host {
                viewModel.addTV(name: found.name, host: host, mac: nil)
                dismiss()
            } else {
                viewModel.errorMessage = "Couldn't determine the IP address for \"\(found.name)\". Try adding it by IP address instead."
            }
        }
    }
}

struct ManualAddView: View {
    @EnvironmentObject private var viewModel: RemoteViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var mac = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Living Room TV)", text: $name)
                    TextField("IP address (e.g. 192.168.1.50)", text: $host)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Find the IP on the TV under Settings → General → Network.")
                }
                Section {
                    TextField("MAC address (optional)", text: $mac)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                } footer: {
                    Text("Used to turn the TV on. Filled in automatically after the first connection, so you can usually leave this empty.")
                }
            }
            .navigationTitle("Add TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.addTV(name: name, host: host, mac: mac)
                        dismiss()
                        viewModel.showSetup = false
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct TVDetailView: View {
    @EnvironmentObject private var viewModel: RemoteViewModel
    @Environment(\.dismiss) private var dismiss
    @State var tv: TVDevice

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $tv.name)
                TextField("IP address", text: $tv.host)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                TextField("MAC address (for power on)", text: Binding(
                    get: { tv.macAddress ?? "" },
                    set: { tv.macAddress = $0.isEmpty ? nil : $0 }
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            }

            Section {
                LabeledContent("Paired", value: tv.clientKey == nil ? "No" : "Yes")
                Button("Pair Again") {
                    tv.clientKey = nil
                    save()
                    viewModel.select(tv)
                    dismiss()
                    viewModel.showSetup = false
                }
            } footer: {
                Text("Re-pairing shows a new approval prompt on the TV.")
            }

            Section {
                Button("Remove This TV", role: .destructive) {
                    viewModel.removeTV(tv)
                    dismiss()
                }
            }
        }
        .navigationTitle(tv.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { save() }
    }

    private func save() {
        viewModel.updateTV(tv)
    }
}
