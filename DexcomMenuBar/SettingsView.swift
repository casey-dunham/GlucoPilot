import SwiftUI

/// Settings window for entering Dexcom credentials
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var selectedRegion: DexcomService.Region = .us
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var onSave: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Dexcom Share Login")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Enter your Dexcom account credentials")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)

            // Form
            VStack(alignment: .leading, spacing: 16) {
                // Username
                VStack(alignment: .leading, spacing: 4) {
                    Text("Username")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Dexcom username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                }

                // Password
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("Dexcom password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                }

                // Region
                VStack(alignment: .leading, spacing: 4) {
                    Text("Region")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Region", selection: $selectedRegion) {
                        ForEach(DexcomService.Region.allCases, id: \.self) { region in
                            Text(region.name).tag(region)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Important note
                VStack(alignment: .leading, spacing: 4) {
                    Label("Important", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text("Dexcom Share must be enabled in your Dexcom app with at least one follower added.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal)

            // Status messages
            if let error = errorMessage {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
            }

            if let success = successMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(success)
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.horizontal)
            }

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(action: testAndSave) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 60)
                    } else {
                        Text("Save")
                            .frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.isEmpty || password.isEmpty || isLoading)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom)
        }
        .frame(width: 350, height: 480)
        .onAppear(perform: loadExistingCredentials)
    }

    private func loadExistingCredentials() {
        if let creds = DexcomService.loadCredentials() {
            username = creds.username
            password = creds.password
            selectedRegion = creds.region
        }
    }

    private func testAndSave() {
        isLoading = true
        errorMessage = nil
        successMessage = nil

        Task {
            let result = await DexcomService.testConnection(
                username: username,
                password: password,
                region: selectedRegion
            )

            await MainActor.run {
                isLoading = false

                switch result {
                case .success(let reading):
                    // Save credentials
                    DexcomService.saveCredentials(
                        username: username,
                        password: password,
                        region: selectedRegion
                    )
                    successMessage = "Connected! Current: \(reading.value) mg/dL \(reading.trendArrow)"

                    // Close after brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        onSave?()
                        dismiss()
                    }

                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

/// Window controller for settings
@MainActor
class SettingsWindowController {
    private var window: NSWindow?

    static let shared = SettingsWindowController()

    func showSettings(onSave: (() -> Void)? = nil) {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(onSave: onSave)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Dexcom Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.isReleasedWhenClosed = false

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func closeSettings() {
        window?.close()
        window = nil
    }
}

#Preview {
    SettingsView()
}
