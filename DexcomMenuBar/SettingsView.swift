import SwiftUI
import AppKit

/// Settings window for entering Dexcom and Nightscout credentials
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // Dexcom settings
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var selectedRegion: DexcomService.Region = .us

    // Nightscout settings
    @State private var nightscoutURL: String = ""
    @State private var nightscoutAPISecret: String = ""
    @State private var nightscoutOTPSecret: String = ""

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var selectedTab = 0

    var onSave: (() -> Void)?

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Dexcom Tab
            dexcomSettingsView
                .tabItem {
                    Label("Dexcom", systemImage: "heart.text.square.fill")
                }
                .tag(0)

            // MARK: - Nightscout Tab
            nightscoutSettingsView
                .tabItem {
                    Label("Nightscout", systemImage: "syringe.fill")
                }
                .tag(1)
        }
        .frame(width: 380, height: 520)
        .onAppear(perform: loadExistingCredentials)
    }

    // MARK: - Dexcom Settings View

    private var dexcomSettingsView: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                Text("Dexcom Share Login")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Enter your Dexcom account credentials")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)

            // Form
            VStack(alignment: .leading, spacing: 14) {
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
            statusMessagesView

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(action: testAndSaveDexcom) {
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
    }

    // MARK: - Nightscout Settings View

    private var nightscoutSettingsView: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "syringe.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)

                Text("Nightscout Remote Bolus")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Configure Nightscout for remote insulin delivery")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)

            // Form
            VStack(alignment: .leading, spacing: 14) {
                // Nightscout URL
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nightscout URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("https://your-nightscout.fly.dev", text: $nightscoutURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }

                // API Secret
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Secret")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("Your Nightscout API secret", text: $nightscoutAPISecret)
                        .textFieldStyle(.roundedBorder)
                }

                // OTP Secret
                VStack(alignment: .leading, spacing: 4) {
                    Text("OTP Secret (from Loop)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("Base32 encoded OTP secret", text: $nightscoutOTPSecret)
                        .textFieldStyle(.roundedBorder)

                    Text("Find this in Loop > Settings > Services > Nightscout > One-Time Password")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Warning
                VStack(alignment: .leading, spacing: 4) {
                    Label("Warning", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)

                    Text("Remote bolus will deliver insulin automatically without confirmation on your phone. Use with caution.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal)

            // Status messages
            statusMessagesView

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                if NightscoutService.hasConfiguration {
                    Button("Clear") {
                        clearNightscout()
                    }
                    .foregroundColor(.red)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(action: saveNightscout) {
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
                .disabled(nightscoutURL.isEmpty || nightscoutAPISecret.isEmpty || nightscoutOTPSecret.isEmpty || isLoading)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom)
        }
    }

    // MARK: - Status Messages

    private var statusMessagesView: some View {
        Group {
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
        }
    }

    private func loadExistingCredentials() {
        // Load Dexcom credentials
        if let creds = DexcomService.loadCredentials() {
            username = creds.username
            password = creds.password
            selectedRegion = creds.region
        }

        // Load Nightscout configuration
        if let config = NightscoutService.loadConfiguration() {
            nightscoutURL = config.url
            nightscoutAPISecret = config.apiSecret
            nightscoutOTPSecret = config.otpSecret
        }
    }

    private func testAndSaveDexcom() {
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

    private func saveNightscout() {
        errorMessage = nil
        successMessage = nil

        // Validate URL format
        var url = nightscoutURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        // Remove trailing slash
        if url.hasSuffix("/") {
            url = String(url.dropLast())
        }

        guard URL(string: url) != nil else {
            errorMessage = "Invalid URL format"
            return
        }

        // Save configuration
        NightscoutService.saveConfiguration(
            url: url,
            apiSecret: nightscoutAPISecret,
            otpSecret: nightscoutOTPSecret
        )

        successMessage = "Nightscout configured! Bolus option now available."

        // Close after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onSave?()
            dismiss()
        }
    }

    private func clearNightscout() {
        NightscoutService.clearConfiguration()
        nightscoutURL = ""
        nightscoutAPISecret = ""
        nightscoutOTPSecret = ""
        successMessage = "Nightscout configuration cleared"

        // Trigger menu rebuild after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onSave?()
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
        window.title = "GlucoPilot Settings"
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
