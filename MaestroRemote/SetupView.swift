import SwiftUI

struct SetupView: View {
    @ObservedObject var client: MaestroClient
    @StateObject private var bonjour = BonjourBrowser()
    @Environment(\.dismiss) private var dismiss
    @State private var manualURL = ""
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Auto Detect").tag(0)
                    Text("Manual").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if tab == 0 {
                    bonjourTab
                } else {
                    manualTab
                }
            }
            .navigationTitle("Connect to Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !client.baseURL.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            manualURL = client.baseURL
            bonjour.startBrowsing()
        }
        .onDisappear { bonjour.stopBrowsing() }
    }

    // MARK: - Bonjour Tab

    private var bonjourTab: some View {
        List {
            Section {
                if bonjour.isSearching && bonjour.discoveredHosts.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Looking for Maestro on your network...")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if bonjour.discoveredHosts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No Maestro found")
                            .fontWeight(.medium)
                        Text("Make sure Maestro is running on your Mac and both devices are on the same Wi-Fi.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(bonjour.discoveredHosts) { host in
                        Button {
                            client.setBaseURL(host.baseURL)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.displayName)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Text(host.baseURL)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            } header: {
                Text("Macs on this network")
            } footer: {
                Text("Maestro advertises itself automatically over Bonjour.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Manual Tab

    private var manualTab: some View {
        Form {
            Section {
                TextField("http://192.168.1.10:27182", text: $manualURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
            } header: {
                Text("Mac Address")
            } footer: {
                Text("Open Maestro on your Mac → right-click the menu bar icon → \"iPhone Connection Info\" to find the URL.")
            }

            Section {
                Button("Connect") {
                    client.setBaseURL(manualURL)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .disabled(manualURL.isEmpty)
            }
        }
    }
}
