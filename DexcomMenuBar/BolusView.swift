import SwiftUI
import AppKit

/// View for entering and sending a remote bolus
struct BolusView: View {
    @State private var bolusAmount: String = ""
    @State private var isLoading = false
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var showConfirmation = false

    var onDismiss: () -> Void

    private let nightscoutService = NightscoutService()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Remote Bolus")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Divider()

            // Bolus input
            HStack {
                Text("Units:")
                    .foregroundColor(.secondary)

                TextField("0.0", text: $bolusAmount)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(size: 18, weight: .medium))
                    .multilineTextAlignment(.center)

                Text("U")
                    .foregroundColor(.secondary)
            }

            // Result message
            if let message = resultMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(isError ? .red : .green)
                    .multilineTextAlignment(.center)
            }

            Divider()

            // Send button
            Button(action: confirmBolus) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(isLoading ? "Sending..." : "Send Bolus")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 112/255, green: 107/255, blue: 255/255))
            .disabled(isLoading || !isValidBolus)

            // Warning
            Text("⚠️ This will deliver insulin via Loop")
                .font(.caption2)
                .foregroundColor(.orange)
        }
        .padding()
        .frame(width: 280)
        .alert("Confirm Bolus", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Deliver \(bolusAmount)u", role: .destructive) {
                sendBolus()
            }
        } message: {
            Text("Are you sure you want to deliver \(bolusAmount) units of insulin? This action cannot be undone.")
        }
    }

    private func confirmBolus() {
        showConfirmation = true
    }

    private var isValidBolus: Bool {
        guard let amount = Double(bolusAmount),
              amount >= 0.05,  // Minimum bolus (most pumps)
              amount <= 30     // Maximum safety limit
        else {
            return false
        }
        return true
    }

    private func sendBolus() {
        guard let amount = Double(bolusAmount), amount > 0 else { return }

        isLoading = true
        resultMessage = nil

        Task {
            let result = await nightscoutService.sendBolus(units: amount)

            await MainActor.run {
                isLoading = false

                switch result {
                case .success(let message):
                    resultMessage = "✓ \(message)"
                    isError = false
                    // Auto-dismiss after success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        onDismiss()
                    }
                case .failure(let error):
                    resultMessage = error.localizedDescription
                    isError = true
                }
            }
        }
    }
}

/// Window controller for bolus entry
@MainActor
class BolusWindowController {
    static let shared = BolusWindowController()

    private var window: NSWindow?

    func showBolus(completion: @escaping () -> Void) {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let bolusView = BolusView {
            self.window?.close()
            self.window = nil
            completion()
        }

        let hostingController = NSHostingController(rootView: bolusView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Remote Bolus"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#Preview {
    BolusView(onDismiss: {})
}
