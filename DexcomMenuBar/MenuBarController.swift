import AppKit
import SwiftUI

/// Controls the menu bar item and its dropdown menu
@MainActor
class MenuBarController: NSObject, ObservableObject, NSMenuDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private let dexcomService = DexcomService()

    @Published private(set) var currentReading: GlucoseReading?
    @Published private(set) var readings: [GlucoseReading] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isLoading = false

    private var refreshTimer: Timer?
    private var chartViewController: ChartMenuItemViewController?
    private var selectedChartRange: ChartTimeRange = .threeHours

    /// Whether to hide the blood sugar value in the menu bar
    private var hideBloodSugar: Bool {
        get { UserDefaults.standard.bool(forKey: "HideBloodSugar") }
        set { UserDefaults.standard.set(newValue, forKey: "HideBloodSugar") }
    }

    /// Polling interval in seconds (5 minutes)
    private let refreshInterval: TimeInterval = 5 * 60

    // MARK: - Initialization

    override init() {
        super.init()
        setupStatusItem()
        startPolling()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "—"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Chart view item
        chartViewController = ChartMenuItemViewController()
        let chartItem = NSMenuItem()
        chartItem.view = chartViewController?.view
        chartItem.tag = 99
        menu.addItem(chartItem)

        menu.addItem(NSMenuItem.separator())

        // Last updated / status item
        let lastUpdatedItem = NSMenuItem(title: "Connecting...", action: nil, keyEquivalent: "")
        lastUpdatedItem.isEnabled = false
        lastUpdatedItem.tag = 100
        menu.addItem(lastUpdatedItem)

        menu.addItem(NSMenuItem.separator())

        // Refresh now
        let refreshItem = NSMenuItem(
            title: "Refresh Now",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // Hide blood sugar toggle
        let hideItem = NSMenuItem(
            title: "Hide Blood Sugar",
            action: #selector(toggleHideBloodSugar),
            keyEquivalent: "h"
        )
        hideItem.target = self
        hideItem.tag = 101
        hideItem.state = hideBloodSugar ? .on : .off
        menu.addItem(hideItem)

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        updateLastUpdatedMenuItem()
        updateMenuBarTitle()
        updateChartView()
    }

    // MARK: - Polling

    private func startPolling() {
        Task {
            await fetchReading()
        }

        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchReading()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Data Fetching

    func fetchReading() async {
        isLoading = true
        updateMenuBarTitle(loading: true)

        // Fetch multiple readings for the chart (12 hours = max we need)
        let chartResult = await dexcomService.fetchReadings(minutes: 720, maxCount: 144)
        if case .success(let fetchedReadings) = chartResult {
            readings = fetchedReadings
            if let latest = fetchedReadings.last {
                currentReading = latest
            }
        }

        // Also get latest single reading
        let result = await dexcomService.fetchLatestReading()

        isLoading = false

        switch result {
        case .success(let reading):
            currentReading = reading
            lastError = nil
            updateMenuBarTitle(reading: reading)
            updateLastUpdatedMenuItem()
            updateChartView()

        case .failure(let error):
            lastError = error.localizedDescription
            currentReading = nil

            if case .noCredentials = error {
                updateMenuBarTitle(needsSetup: true)
            } else if let cached = await dexcomService.getCachedReading() {
                updateMenuBarTitle(reading: cached, stale: true)
            } else {
                updateMenuBarTitle(error: true)
            }
            updateLastUpdatedMenuItem()
            updateChartView()
            print("[MenuBar] Error: \(error.localizedDescription)")
        }
    }

    // MARK: - UI Updates

    private func updateMenuBarTitle(
        reading: GlucoseReading? = nil,
        stale: Bool = false,
        loading: Bool = false,
        error: Bool = false,
        needsSetup: Bool = false
    ) {
        guard let button = statusItem?.button else { return }

        if loading {
            button.title = "• • •"
            return
        }

        if needsSetup {
            button.title = "⚙️"
            return
        }

        let displayReading = reading ?? currentReading

        if error && displayReading == nil {
            button.title = "—"
            return
        }

        guard let reading = displayReading else {
            button.title = "—"
            return
        }

        var title: String

        if hideBloodSugar {
            // Just show trend arrow when hiding blood sugar
            title = reading.trendArrow
        } else {
            title = reading.menuBarDisplay

            // Add red dot for low blood sugar (below 70)
            if reading.value < 70 {
                title = "🔴 " + title
            }
        }

        if stale || reading.isVeryStale {
            title += " ⚠️"
        } else if reading.isStale {
            title += " ⏳"
        }

        button.title = title
    }

    private func updateLastUpdatedMenuItem() {
        guard let menu = statusItem?.menu,
              let lastUpdatedItem = menu.item(withTag: 100) else { return }

        if let reading = currentReading {
            var timeText = "Last updated: \(reading.timeAgoString)"
            if reading.isVeryStale {
                timeText += " ⚠️ Check sensor"
            } else if reading.isStale {
                timeText += " ⏳"
            }
            lastUpdatedItem.title = timeText
            lastUpdatedItem.action = nil
            lastUpdatedItem.isEnabled = false

        } else if let error = lastError {
            let truncatedError = error.count > 45 ? String(error.prefix(42)) + "..." : error
            lastUpdatedItem.title = truncatedError

            if error.contains("credentials") || error.contains("Click here") {
                lastUpdatedItem.action = #selector(openSettings)
                lastUpdatedItem.target = self
                lastUpdatedItem.isEnabled = true
            } else {
                lastUpdatedItem.action = nil
                lastUpdatedItem.isEnabled = false
            }
        } else {
            lastUpdatedItem.title = "Connecting..."
            lastUpdatedItem.action = nil
            lastUpdatedItem.isEnabled = false
        }
    }

    private func updateChartView() {
        chartViewController?.updateReadings(readings)
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        Task {
            await dexcomService.clearSession()
            await fetchReading()
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showSettings { [weak self] in
            Task { @MainActor [weak self] in
                await self?.dexcomService.clearSession()
                await self?.fetchReading()
            }
        }
    }

    @objc private func toggleHideBloodSugar() {
        hideBloodSugar.toggle()
        if let menu = statusItem?.menu,
           let hideItem = menu.item(withTag: 101) {
            hideItem.state = hideBloodSugar ? .on : .off
        }
        updateMenuBarTitle()
    }

    @objc private func quit() {
        stopPolling()
        NSApplication.shared.terminate(nil)
    }
}
