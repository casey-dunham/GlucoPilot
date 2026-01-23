import SwiftUI
import Charts

/// Time range options for the glucose chart
enum ChartTimeRange: Int, CaseIterable {
    case oneHour = 60
    case threeHours = 180
    case sixHours = 360
    case twelveHours = 720

    var label: String {
        switch self {
        case .oneHour: return "1H"
        case .threeHours: return "3H"
        case .sixHours: return "6H"
        case .twelveHours: return "12H"
        }
    }
}

/// A compact glucose chart view for the menu bar dropdown
struct GlucoseChartView: View {
    let readings: [GlucoseReading]
    @Binding var selectedRange: ChartTimeRange
    @Environment(\.colorScheme) var colorScheme

    // Threshold values
    private let lowThreshold: Int = 70
    private let highThreshold: Int = 180

    /// Periwinkle color for in-range status (#706bff)
    private let periwinkle = Color(red: 112/255, green: 107/255, blue: 255/255)

    /// Main line color - adapts to color scheme
    private var lineColor: Color {
        colorScheme == .dark ? .white : periwinkle
    }

    /// Target zone color
    private var targetZoneColor: Color {
        periwinkle.opacity(colorScheme == .dark ? 0.15 : 0.2)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Time range picker
            Picker("Time Range", selection: $selectedRange) {
                ForEach(ChartTimeRange.allCases, id: \.self) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Chart
            if filteredReadings.isEmpty {
                Text("No data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 140)
            } else {
                Chart {
                    // Target range background (70-180)
                    RectangleMark(
                        xStart: nil,
                        xEnd: nil,
                        yStart: .value("Low", lowThreshold),
                        yEnd: .value("High", highThreshold)
                    )
                    .foregroundStyle(targetZoneColor)

                    // Glucose dots (Dexcom style - small white dots)
                    ForEach(filteredReadings, id: \.timestamp) { reading in
                        PointMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("Glucose", reading.value)
                        )
                        .foregroundStyle(.white)
                        .symbolSize(dotSize)
                    }

                    // Larger dot at current reading (latest point) with status color
                    if let latest = filteredReadings.last {
                        PointMark(
                            x: .value("Time", latest.timestamp),
                            y: .value("Glucose", latest.value)
                        )
                        .foregroundStyle(statusColor(for: latest.value))
                        .symbolSize(currentDotSize)
                    }
                }
                .chartYScale(domain: yAxisRange)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: xAxisHourStride)) { _ in
                        AxisValueLabel(format: .dateTime.hour())
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: yAxisValues) { _ in
                        AxisValueLabel()
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 140)
            }

            // Current reading display
            if let latest = filteredReadings.last ?? readings.last {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: latest.value))
                        .frame(width: 10, height: 10)

                    Text("\(latest.value)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(statusColor(for: latest.value))

                    Text(latest.trendArrow)
                        .font(.system(size: 18))

                    Spacer()

                    Text(latest.timeAgoString)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    /// Filter readings to the selected time range
    private var filteredReadings: [GlucoseReading] {
        let cutoff = Date().addingTimeInterval(-Double(selectedRange.rawValue) * 60)
        return readings.filter { $0.timestamp >= cutoff }
    }

    /// X-axis hour stride based on time range
    private var xAxisHourStride: Int {
        switch selectedRange {
        case .oneHour: return 1
        case .threeHours: return 1
        case .sixHours: return 2
        case .twelveHours: return 3
        }
    }

    /// Dot size based on time range (larger for 1 hour view)
    private var dotSize: CGFloat {
        switch selectedRange {
        case .oneHour: return 25
        case .threeHours: return 15
        case .sixHours: return 15
        case .twelveHours: return 15
        }
    }

    /// Current reading dot size
    private var currentDotSize: CGFloat {
        switch selectedRange {
        case .oneHour: return 50
        case .threeHours: return 40
        case .sixHours: return 40
        case .twelveHours: return 40
        }
    }

    /// Calculate Y axis range based on data
    private var yAxisRange: ClosedRange<Int> {
        guard !filteredReadings.isEmpty else { return 60...200 }

        let values = filteredReadings.map { $0.value }
        let dataMin = values.min() ?? 100
        let dataMax = values.max() ?? 150

        // Ensure we show the target zone
        let minValue = max(40, min(dataMin - 10, lowThreshold - 5))
        let maxValue = min(350, max(dataMax + 10, highThreshold + 10))

        return minValue...maxValue
    }

    /// Generate clean Y axis values
    private var yAxisValues: [Int] {
        let range = yAxisRange
        let span = range.upperBound - range.lowerBound

        let step: Int
        if span <= 60 {
            step = 10
        } else if span <= 100 {
            step = 20
        } else if span <= 150 {
            step = 30
        } else {
            step = 50
        }

        var values: [Int] = []
        var current = ((range.lowerBound / step) + 1) * step
        while current < range.upperBound {
            values.append(current)
            current += step
        }
        return values
    }

    /// Status color based on glucose value
    private func statusColor(for value: Int) -> Color {
        if value < lowThreshold {
            return .red
        } else if value > highThreshold {
            return .yellow
        } else {
            return periwinkle
        }
    }
}

/// Menu item that contains the chart
@MainActor
class ChartMenuItemViewController: NSViewController {
    private var hostingView: NSHostingView<GlucoseChartView>?
    private var readings: [GlucoseReading] = []
    private var selectedRange: ChartTimeRange = .threeHours

    override func loadView() {
        let chartView = GlucoseChartView(
            readings: readings,
            selectedRange: Binding(
                get: { self.selectedRange },
                set: { self.selectedRange = $0 }
            )
        )
        let hosting = NSHostingView(rootView: chartView)
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 220)
        self.view = hosting
        self.hostingView = hosting
    }

    func updateReadings(_ newReadings: [GlucoseReading]) {
        self.readings = newReadings
        updateChartView()
    }

    private func updateChartView() {
        let chartView = GlucoseChartView(
            readings: readings,
            selectedRange: Binding(
                get: { self.selectedRange },
                set: { newValue in
                    self.selectedRange = newValue
                    self.updateChartView()
                }
            )
        )
        hostingView?.rootView = chartView
    }
}

#Preview {
    GlucoseChartView(
        readings: (0..<36).map { i in
            GlucoseReading(
                value: 110 + Int.random(in: -20...40),
                trend: "Flat",
                timestamp: Date().addingTimeInterval(-Double(35 - i) * 5 * 60)
            )
        },
        selectedRange: .constant(.threeHours)
    )
}
