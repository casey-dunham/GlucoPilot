import Foundation
import CryptoKit

/// Service for communicating with Nightscout and sending remote commands
actor NightscoutService {

    // MARK: - Configuration Keys

    private static let urlKey = "NightscoutURL"

    // MARK: - Errors

    enum NightscoutError: LocalizedError {
        case noConfiguration
        case invalidURL
        case invalidOTPSecret
        case networkError(Error)
        case serverError(String)
        case unauthorized

        var errorDescription: String? {
            switch self {
            case .noConfiguration:
                return "Nightscout not configured"
            case .invalidURL:
                return "Invalid Nightscout URL"
            case .invalidOTPSecret:
                return "Invalid OTP secret"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .serverError(let message):
                return "Server error: \(message)"
            case .unauthorized:
                return "Unauthorized - check API secret"
            }
        }
    }

    // MARK: - Configuration Management

    static func saveConfiguration(url: String, apiSecret: String, otpSecret: String) {
        UserDefaults.standard.set(url, forKey: urlKey)

        // Store API secret in Keychain
        saveToKeychain(account: "NightscoutAPISecret", data: apiSecret)

        // Store OTP secret in Keychain
        saveToKeychain(account: "NightscoutOTP", data: otpSecret)
    }

    private static func saveToKeychain(account: String, data: String) {
        guard let secretData = data.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "GlucoPilot"
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = secretData
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "GlucoPilot",
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func loadConfiguration() -> (url: String, apiSecret: String, otpSecret: String)? {
        guard let url = UserDefaults.standard.string(forKey: urlKey),
              !url.isEmpty,
              let apiSecret = loadFromKeychain(account: "NightscoutAPISecret"),
              !apiSecret.isEmpty,
              let otpSecret = loadFromKeychain(account: "NightscoutOTP"),
              !otpSecret.isEmpty else {
            return nil
        }

        return (url, apiSecret, otpSecret)
    }

    static var hasConfiguration: Bool {
        return loadConfiguration() != nil
    }

    static func clearConfiguration() {
        UserDefaults.standard.removeObject(forKey: urlKey)

        // Clear API secret from Keychain
        deleteFromKeychain(account: "NightscoutAPISecret")

        // Clear OTP secret from Keychain
        deleteFromKeychain(account: "NightscoutOTP")
    }

    private static func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "GlucoPilot"
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - OTP Generation (TOTP)

    /// Generates a Time-based One-Time Password
    static func generateOTP(secret: String) -> String? {
        // Remove spaces and convert to uppercase
        let cleanSecret = secret.replacingOccurrences(of: " ", with: "").uppercased()

        // Decode base32 secret
        guard let secretData = base32Decode(cleanSecret) else {
            print("[OTP] Failed to decode base32 secret")
            return nil
        }

        // Get current time step (30-second intervals)
        let timeStep = UInt64(Date().timeIntervalSince1970 / 30)

        // Convert time to big-endian bytes
        var timeBytes = timeStep.bigEndian
        let timeData = Data(bytes: &timeBytes, count: 8)

        // Generate HMAC-SHA1
        let key = SymmetricKey(data: secretData)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: timeData, using: key)
        let hmacData = Data(hmac)

        // Dynamic truncation
        let offset = Int(hmacData[hmacData.count - 1] & 0x0f)
        let truncatedHash = hmacData.subdata(in: offset..<(offset + 4))

        var number = truncatedHash.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        number &= 0x7fffffff
        number = number % 1000000

        return String(format: "%06d", number)
    }

    /// Decodes a base32 string to Data
    private static func base32Decode(_ string: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = ""

        for char in string {
            if char == "=" { continue }
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            let value = alphabet.distance(from: alphabet.startIndex, to: index)
            bits += String(value, radix: 2).leftPadded(to: 5, with: "0")
        }

        var data = Data()
        var index = bits.startIndex
        while bits.distance(from: index, to: bits.endIndex) >= 8 {
            let endIndex = bits.index(index, offsetBy: 8)
            if let byte = UInt8(String(bits[index..<endIndex]), radix: 2) {
                data.append(byte)
            }
            index = endIndex
        }

        return data
    }

    // MARK: - Remote Bolus

    /// Sends a remote bolus command via Nightscout
    func sendBolus(units: Double) async -> Result<String, NightscoutError> {
        guard let config = Self.loadConfiguration() else {
            return .failure(.noConfiguration)
        }

        guard let baseURL = URL(string: config.url) else {
            return .failure(.invalidURL)
        }

        guard let otp = Self.generateOTP(secret: config.otpSecret) else {
            return .failure(.invalidOTPSecret)
        }

        // Use the Loop notifications API to trigger push notification
        let url = baseURL.appendingPathComponent("api/v2/notifications/loop")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // API secret as SHA1 hash
        let apiSecretHash = SHA1Hash(config.apiSecret)
        request.setValue(apiSecretHash, forHTTPHeaderField: "api-secret")

        // Create bolus payload for Loop notification
        let now = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any] = [
            "enteredBy": "GlucoPilot",
            "eventType": "Remote Bolus Entry",
            "remoteBolus": units,
            "created_at": now,
            "otp": otp
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            print("[Nightscout] Sending bolus: \(units)u with OTP: \(otp)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.serverError("Invalid response"))
            }

            let responseString = String(data: data, encoding: .utf8) ?? ""
            print("[Nightscout] Response (\(httpResponse.statusCode)): \(responseString)")

            switch httpResponse.statusCode {
            case 200, 201:
                return .success("Bolus of \(units)u sent successfully")
            case 401:
                return .failure(.unauthorized)
            default:
                return .failure(.serverError("HTTP \(httpResponse.statusCode): \(responseString)"))
            }

        } catch {
            return .failure(.networkError(error))
        }
    }

    /// Fetches current Loop status from Nightscout
    func fetchLoopStatus() async -> Result<LoopStatus, NightscoutError> {
        guard let config = Self.loadConfiguration() else {
            return .failure(.noConfiguration)
        }

        guard let baseURL = URL(string: config.url) else {
            return .failure(.invalidURL)
        }

        let url = baseURL.appendingPathComponent("api/v1/devicestatus.json")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.invalidURL)
        }
        components.queryItems = [URLQueryItem(name: "count", value: "1")]

        guard let requestURL = components.url else {
            return .failure(.invalidURL)
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let statuses = try JSONDecoder().decode([DeviceStatus].self, from: data)

            if let status = statuses.first, let loop = status.loop {
                return .success(LoopStatus(
                    iob: loop.iob?.iob ?? 0,
                    cob: loop.cob?.cob ?? 0,
                    timestamp: status.createdAt
                ))
            }

            return .failure(.serverError("No Loop data available"))
        } catch {
            return .failure(.networkError(error))
        }
    }

    // MARK: - Helper Functions

    private func SHA1Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.SHA1.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - String Extension

extension String {
    func leftPadded(to length: Int, with character: Character) -> String {
        if self.count >= length { return self }
        return String(repeating: character, count: length - self.count) + self
    }
}

// MARK: - Nightscout Data Models

struct LoopStatus {
    let iob: Double
    let cob: Double
    let timestamp: String
}

struct DeviceStatus: Codable {
    let createdAt: String
    let loop: LoopData?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case loop
    }
}

struct LoopData: Codable {
    let iob: IOBData?
    let cob: COBData?
}

struct IOBData: Codable {
    let iob: Double
}

struct COBData: Codable {
    let cob: Double
}
