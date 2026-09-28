import SwiftUI

// Droplet detail options for LocalSend (Settings › Droplets › LocalSend).
// Anchors are "droplet.localSend.<option>", indexed in SettingsSearch.

struct LocalSendDropletSettings: View {
    @ObservedObject private var localSendSettings = LocalSendSettings.shared
    @ObservedObject private var service = LocalSendService.shared
    @State private var name = ""
    /// The favorite waiting on "Forget" to be confirmed.
    @State private var forgetting: LocalSendFavoriteID?

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: 6) {
                    TextField("Device name", text: $name, prompt: Text(LocalSendService.macName))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit { localSendSettings.deviceName = name.trimmingCharacters(in: .whitespaces) }
                    Button("Reset") {
                        name = ""
                        localSendSettings.deviceName = ""
                    }
                    .disabled(localSendSettings.deviceName.isEmpty && name.isEmpty)
                    .help("Use this Mac's name")
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Device name")
                    InfoButton("The name other devices see in LocalSend. Press Return to save it.")
                }
            }
            .settingsAnchor("droplet.localSend.name")
            .onAppear { name = localSendSettings.deviceName }
            // Saved on Return, or when the page closes; not per keystroke,
            // since each change is announced to the network.
            .onDisappear {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if trimmed != localSendSettings.deviceName { localSendSettings.deviceName = trimmed }
            }
            InfoToggle("Visible to other devices",
                       info: "Announcing this Mac on the local network, and answering other devices' scans. Off, this Mac can still send and find devices, but others won't list it.",
                       isOn: $localSendSettings.isVisible)
                .settingsAnchor("droplet.localSend.visible")
            Picker(selection: $localSendSettings.receiveMode) {
                ForEach(LocalSendReceiveMode.allCases) { Text($0.title).tag($0) }
            } label: {
                HStack(spacing: 6) {
                    Text("Receive from")
                    InfoButton(localSendSettings.receiveMode.detail)
                }
            }
            .settingsAnchor("droplet.localSend.receive")
            InfoToggle("Quick Save for favorites",
                       info: "Transfers from your favorite devices are saved right away, without the Incoming requests prompt.",
                       isOn: $localSendSettings.quickSaveFavorites)
                .disabled(localSendSettings.receiveMode == .off)
                .settingsAnchor("droplet.localSend.quickSave")
            if localSendSettings.receiveMode == .off {
                Text("Receiving is off.").font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent {
                TextField("None", text: $localSendSettings.pin)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            } label: {
                HStack(spacing: 6) {
                    Text("PIN")
                    InfoButton("Senders must type this PIN before a transfer is offered to you. Leave it empty for no PIN. Five wrong tries in a minute are refused.")
                }
            }
            .settingsAnchor("droplet.localSend.pin")
        } header: {
            Text("Receiving")
        } footer: {
            Text(localSendSettings.receiveMode.detail).font(.caption).foregroundStyle(.secondary)
        }

        Section {
            LabeledContent {
                HStack(spacing: 6) {
                    Text(service.saveFolder.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .help(service.saveFolder.path)
                    Button("Choose…") { chooseFolder() }
                    if !localSendSettings.saveFolder.isEmpty {
                        Button("Downloads") { localSendSettings.saveFolder = "" }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Save received files to")
                    InfoButton("Where incoming files are written. Folders a sender shares keep their structure inside it.")
                }
            }
            .settingsAnchor("droplet.localSend.folder")
            InfoToggle("Add received files to the shelf",
                       info: "Finished transfers also appear on your notch shelf, in the Tray.",
                       isOn: $localSendSettings.addToShelf)
                .settingsAnchor("droplet.localSend.shelf")
        } header: {
            Text("Files")
        }

        Section {
            LabeledContent {
                HStack(spacing: 6) {
                    if let offer = service.offer {
                        Text("\(offer.files.count) file\(offer.files.count == 1 ? "" : "s") · \(service.offerURL ?? "no network")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Stop") { service.stopOffer() }
                    } else {
                        Text("Not sharing").foregroundStyle(.secondary)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Share in a browser")
                    InfoButton("Stage files in the LocalSend widget and click Browser. Tama then holds them behind a plain web page on port 53317, so a device with no LocalSend installed can download them by typing this Mac's address. The PIN, if you set one, guards the page too.")
                }
            }
            .settingsAnchor("droplet.localSend.browser")
        } header: {
            Text("Sharing")
        } footer: {
            Text("Tama also answers LocalSend's older v1 API, so devices still running LocalSend 1.x can send to this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            InfoToggle("Encrypted (HTTPS)",
                       info: "Transfers use HTTPS with a certificate made on this Mac and kept in your login keychain as \"Tama LocalSend TLS\". Off, they use plain HTTP, which older or web clients may need.",
                       isOn: $localSendSettings.isEncrypted)
                .settingsAnchor("droplet.localSend.encrypted")
            LabeledContent("Fingerprint") {
                Text(service.fingerprint.map { String($0.prefix(23)) + "…" } ?? "Fingerprint appears once the receiver runs.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .help(service.fingerprint ?? "")
            }
            LabeledContent("Receiver") {
                Text(receiverText).foregroundStyle(receiverColor).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Transfer security")
        } footer: {
            Text("LocalSend works on the same network, no internet needed. It listens on port 53317 (TCP and UDP multicast 224.0.0.167) while this droplet is on; macOS may ask once to allow Local Network access. If the LocalSend app itself runs on this Mac, quit it first — only one can use the port. After an ad-hoc rebuild of Tama, macOS may ask once to let it use its keychain key.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            if service.favorites.isEmpty {
                Text("No known devices yet. Right-click a device in the LocalSend widget to add it to your favorites.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(service.favorites) { favorite in
                HStack(spacing: 8) {
                    Image(systemName: favorite.symbol).frame(width: 20).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(favorite.alias)
                        Text(favorite.deviceModel ?? favorite.deviceType?.capitalized ?? "Device")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Forget…", role: .destructive) {
                        forgetting = LocalSendFavoriteID(fingerprint: favorite.fingerprint, alias: favorite.alias)
                    }
                    .controlSize(.small)
                    .help("Forget this device")
                    .accessibilityLabel("Forget \(favorite.alias)")
                }
            }
        } header: {
            Text("Favorites")
        }
        .settingsAnchor("droplet.localSend.favorites")
        .confirmationDialog("Forget \(forgetting?.alias ?? "this device")?",
                            isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                            presenting: forgetting) { device in
            Button("Forget Device", role: .destructive) { service.forget(device.fingerprint) }
        } message: { _ in
            Text("It leaves your favorites. Right-click it in the LocalSend widget to add it again.")
        }
    }

    private var receiverText: String {
        switch service.receiverState {
        case .off: "Off — turn LocalSend on to receive and find devices."
        case .starting: "Starting the receiver…"
        case .running: "Running on port 53317"
        case let .failed(message): message
        }
    }

    private var receiverColor: Color {
        switch service.receiverState {
        case .failed: .red
        case .running: .green
        default: .secondary
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where received files are saved"
        panel.directoryURL = service.saveFolder
        if panel.runModal() == .OK, let url = panel.url { localSendSettings.saveFolder = url.path }
    }
}

/// A favorite device picked for "Forget", held while the dialog asks.
private struct LocalSendFavoriteID: Equatable {
    let fingerprint: String
    let alias: String
}
