import Foundation

/// Represents a single glucose reading from the Dexcom CGM
struct GlucoseReading: Codable {
    let value: Int           // Glucose value in mg/dL
    let trend: String        // Trend direction string from API
    let timestamp: Date      // When the reading was taken

    /// Converts the Dexcom trend string to a display arrow
    var trendArrow: String {
        switch trend {
        case "DoubleUp":
            return "⇈"
        case "SingleUp":
            return "↑"
        case "FortyFiveUp":
            return "↗"
        case "Flat":
            return "→"
        case "FortyFiveDown":
            return "↘"
        case "SingleDown":
            return "↓"
        case "DoubleDown":
            return "⇊"
        case "NotComputable", "NOT COMPUTABLE", "RateOutOfRange", "RATE OUT OF RANGE":
            return "?"
        case "None", "NONE", "":
            return "•"  // No trend data available
        default:
            return "—"
        }
    }

    /// Whether this reading is stale (older than 10 minutes)
    var isStale: Bool {
        return minutesAgo > 10
    }

    /// Whether this reading is very stale (older than 20 minutes - likely sensor issue)
    var isVeryStale: Bool {
        return minutesAgo > 20
    }

    /// Formatted display string for the menu bar
    var menuBarDisplay: String {
        return "\(value) \(trendArrow)"
    }

    /// How long ago the reading was taken
    var minutesAgo: Int {
        return Int(-timestamp.timeIntervalSinceNow / 60)
    }

    /// Human-readable time since reading
    var timeAgoString: String {
        let minutes = minutesAgo
        if minutes < 1 {
            return "just now"
        } else if minutes == 1 {
            return "1 min ago"
        } else {
            return "\(minutes) min ago"
        }
    }
}

/// Response structure from Dexcom authentication
struct DexcomAuthResponse: Codable {
    let accountId: String

    enum CodingKeys: String, CodingKey {
        case accountId = "AccountId"
    }
}

/// Raw glucose reading from the Dexcom API
struct DexcomGlucoseResponse: Codable {
    let value: Int
    let trend: String
    let wt: String  // Timestamp in format "/Date(1234567890000)/"

    enum CodingKeys: String, CodingKey {
        case value = "Value"
        case trend = "Trend"
        case wt = "WT"
    }

    /// Parses the Dexcom timestamp format to a Date
    var timestamp: Date? {
        // Format can be: /Date(1234567890000)/ OR Date(1234567890000) OR Date(1234567890000-0500)
        // Extract just the milliseconds number
        let pattern = #"Date\((\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: wt, range: NSRange(wt.startIndex..., in: wt)),
              let range = Range(match.range(at: 1), in: wt),
              let milliseconds = Double(wt[range]) else {
            print("[Parse] Failed to parse timestamp: \(wt)")
            return nil
        }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    /// Converts to our domain model
    func toGlucoseReading() -> GlucoseReading? {
        guard let date = timestamp else { return nil }
        return GlucoseReading(value: value, trend: trend, timestamp: date)
    }
}
