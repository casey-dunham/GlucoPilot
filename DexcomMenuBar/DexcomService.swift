import Foundation
import Security

/// Service for communicating with the Dexcom Share API
/// Based on pydexcom: https://github.com/gagebenne/pydexcom
actor DexcomService {

    // MARK: - Configuration

    /// Dexcom application IDs
    private static let applicationIdUS = "d89443d2-327c-4a6f-89e5-496bbb0317db"
    private static let applicationIdJP = "d8665ade-9673-4e27-9ff6-92db4ce13d13"

    /// Available Dexcom Share server endpoints
    enum Region: Int, CaseIterable {
        case us = 0
        case us1 = 1      // Alternative US server
        case ous = 2      // Outside US
        case japan = 3

        var name: String {
            switch self {
            case .us: return "US (share2)"
            case .us1: return "US (share1)"
            case .ous: return "Outside US"
            case .japan: return "Japan"
            }
        }

        var baseURL: String {
            switch self {
            case .us: return "https://share2.dexcom.com/ShareWebServices/Services"
            case .us1: return "https://share1.dexcom.com/ShareWebServices/Services"
            case .ous: return "https://shareous1.dexcom.com/ShareWebServices/Services"
            case .japan: return "https://share.dexcom.jp/ShareWebServices/Services"
            }
        }

        var applicationId: String {
            switch self {
            case .us, .us1, .ous: return applicationIdUS
            case .japan: return applicationIdJP
            }
        }
    }

    // MARK: - Credential Storage Keys

    private static let usernameKey = "DexcomUsername"
    private static let regionKey = "DexcomRegion"

    // MARK: - State

    private var sessionId: String?
    private var accountId: String?
    private var lastReading: GlucoseReading?
    private var currentRegion: Region = .us

    // MARK: - Errors

    enum DexcomError: LocalizedError {
        case noCredentials
        case invalidCredentials
        case authenticationFailed(String)
        case networkError(Error)
        case noReadingsAvailable
        case invalidResponse
        case sessionExpired
        case shareNotEnabled

        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "Click here to enter Dexcom credentials"
            case .invalidCredentials:
                return "Invalid username or password"
            case .authenticationFailed(let message):
                return "Login failed: \(message)"
            case .networkError(let error):
                return "Network: \(error.localizedDescription)"
            case .noReadingsAvailable:
                return "No readings - enable Share with a follower"
            case .invalidResponse:
                return "Invalid response from Dexcom"
            case .sessionExpired:
                return "Session expired"
            case .shareNotEnabled:
                return "Enable Dexcom Share with at least one follower"
            }
        }
    }

    // MARK: - Credential Management

    /// Saves credentials to UserDefaults (username) and Keychain (password)
    static func saveCredentials(username: String, password: String, region: Region) {
        UserDefaults.standard.set(username, forKey: usernameKey)
        UserDefaults.standard.set(region.rawValue, forKey: regionKey)

        // Save password to Keychain
        let passwordData = password.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "DexcomMenuBar",
            kSecAttrService as String: "DexcomShare"
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = passwordData
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Loads credentials from storage
    static func loadCredentials() -> (username: String, password: String, region: Region)? {
        guard let username = UserDefaults.standard.string(forKey: usernameKey),
              !username.isEmpty else {
            return nil
        }

        let regionRaw = UserDefaults.standard.integer(forKey: regionKey)
        let region = Region(rawValue: regionRaw) ?? .us

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "DexcomMenuBar",
            kSecAttrService as String: "DexcomShare",
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            return nil
        }

        return (username, password, region)
    }

    static var hasCredentials: Bool {
        return loadCredentials() != nil
    }

    static func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: regionKey)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "DexcomMenuBar",
            kSecAttrService as String: "DexcomShare"
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Public API

    func fetchLatestReading() async -> Result<GlucoseReading, DexcomError> {
        guard let credentials = Self.loadCredentials() else {
            return .failure(.noCredentials)
        }

        currentRegion = credentials.region

        do {
            if sessionId == nil {
                try await authenticate(username: credentials.username, password: credentials.password)
            }

            let reading = try await fetchGlucose()
            lastReading = reading
            return .success(reading)

        } catch let error as DexcomError {
            if case .sessionExpired = error {
                sessionId = nil
                accountId = nil
                do {
                    try await authenticate(username: credentials.username, password: credentials.password)
                    let reading = try await fetchGlucose()
                    lastReading = reading
                    return .success(reading)
                } catch let retryError as DexcomError {
                    return .failure(retryError)
                } catch {
                    return .failure(.networkError(error))
                }
            }
            return .failure(error)
        } catch {
            return .failure(.networkError(error))
        }
    }

    func getCachedReading() -> GlucoseReading? {
        return lastReading
    }

    func clearSession() {
        sessionId = nil
        accountId = nil
    }

    /// Fetches multiple glucose readings for chart display
    func fetchReadings(minutes: Int, maxCount: Int) async -> Result<[GlucoseReading], DexcomError> {
        guard let credentials = Self.loadCredentials() else {
            return .failure(.noCredentials)
        }

        currentRegion = credentials.region

        do {
            if sessionId == nil {
                try await authenticate(username: credentials.username, password: credentials.password)
            }

            let readings = try await fetchMultipleGlucose(minutes: minutes, maxCount: maxCount)
            return .success(readings)

        } catch let error as DexcomError {
            if case .sessionExpired = error {
                sessionId = nil
                accountId = nil
                do {
                    try await authenticate(username: credentials.username, password: credentials.password)
                    let readings = try await fetchMultipleGlucose(minutes: minutes, maxCount: maxCount)
                    return .success(readings)
                } catch let retryError as DexcomError {
                    return .failure(retryError)
                } catch {
                    return .failure(.networkError(error))
                }
            }
            return .failure(error)
        } catch {
            return .failure(.networkError(error))
        }
    }

    /// Fetches multiple glucose readings
    private func fetchMultipleGlucose(minutes: Int, maxCount: Int) async throws -> [GlucoseReading] {
        guard let sessionId = sessionId else {
            throw DexcomError.sessionExpired
        }

        var components = URLComponents(string: "\(baseURL)/Publisher/ReadPublisherLatestGlucoseValues")!
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "minutes", value: String(minutes)),
            URLQueryItem(name: "maxCount", value: String(maxCount))
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data()
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DexcomError.invalidResponse
        }

        if httpResponse.statusCode == 500 {
            let errorMessage = String(data: data, encoding: .utf8) ?? ""
            if errorMessage.contains("SessionIdNotFound") || errorMessage.contains("SessionNotValid") {
                throw DexcomError.sessionExpired
            }
        }

        guard httpResponse.statusCode == 200 else {
            throw DexcomError.invalidResponse
        }

        let decoder = JSONDecoder()
        let rawReadings = try decoder.decode([DexcomGlucoseResponse].self, from: data)

        // Convert and sort by timestamp (newest first from API, but we want oldest first for chart)
        let readings = rawReadings.compactMap { $0.toGlucoseReading() }.reversed()
        return Array(readings)
    }

    /// Tests connection with given credentials
    static func testConnection(username: String, password: String, region: Region) async -> Result<GlucoseReading, DexcomError> {
        let service = DexcomService()
        return await service.testCredentials(username: username, password: password, region: region)
    }

    private func testCredentials(username: String, password: String, region: Region) async -> Result<GlucoseReading, DexcomError> {
        currentRegion = region
        do {
            try await authenticate(username: username, password: password)
            let reading = try await fetchGlucose()
            return .success(reading)
        } catch let error as DexcomError {
            return .failure(error)
        } catch {
            return .failure(.networkError(error))
        }
    }

    // MARK: - Private Methods

    private var baseURL: String { currentRegion.baseURL }
    private var applicationId: String { currentRegion.applicationId }

    /// Two-step authentication: 1) Get account ID, 2) Get session ID
    private func authenticate(username: String, password: String) async throws {
        // Step 1: Get Account ID
        let acctId = try await getAccountId(username: username, password: password)
        self.accountId = acctId

        // Step 2: Get Session ID
        let sessId = try await getSessionId(accountId: acctId, password: password)
        self.sessionId = sessId
    }

    /// Step 1: AuthenticatePublisherAccount - returns account ID
    private func getAccountId(username: String, password: String) async throws -> String {
        let url = URL(string: "\(baseURL)/General/AuthenticatePublisherAccount")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "accountName": username,
            "password": password,
            "applicationId": applicationId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[Dexcom] Step 1: Getting account ID from \(currentRegion.name)...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DexcomError.invalidResponse
        }

        let responseString = String(data: data, encoding: .utf8) ?? ""
        print("[Dexcom] Account ID response (\(httpResponse.statusCode)): \(responseString.prefix(100))")

        guard httpResponse.statusCode == 200 else {
            if responseString.contains("AccountPasswordInvalid") ||
               responseString.contains("SSO_AuthenticateAccountNotFound") ||
               responseString.contains("AccountNotFound") {
                throw DexcomError.invalidCredentials
            }
            throw DexcomError.authenticationFailed(responseString)
        }

        let accountId = responseString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        guard !accountId.isEmpty, accountId != "00000000-0000-0000-0000-000000000000" else {
            throw DexcomError.invalidCredentials
        }

        print("[Dexcom] Got account ID: \(accountId.prefix(8))...")
        return accountId
    }

    /// Step 2: LoginPublisherAccountById - returns session ID
    private func getSessionId(accountId: String, password: String) async throws -> String {
        let url = URL(string: "\(baseURL)/General/LoginPublisherAccountById")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "accountId": accountId,
            "password": password,
            "applicationId": applicationId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[Dexcom] Step 2: Getting session ID...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DexcomError.invalidResponse
        }

        let responseString = String(data: data, encoding: .utf8) ?? ""
        print("[Dexcom] Session ID response (\(httpResponse.statusCode)): \(responseString.prefix(100))")

        guard httpResponse.statusCode == 200 else {
            throw DexcomError.authenticationFailed(responseString)
        }

        let sessionId = responseString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        guard !sessionId.isEmpty, sessionId != "00000000-0000-0000-0000-000000000000" else {
            throw DexcomError.invalidCredentials
        }

        print("[Dexcom] Got session ID: \(sessionId.prefix(8))...")
        return sessionId
    }

    /// Fetches the latest glucose reading
    private func fetchGlucose() async throws -> GlucoseReading {
        guard let sessionId = sessionId else {
            throw DexcomError.sessionExpired
        }

        var components = URLComponents(string: "\(baseURL)/Publisher/ReadPublisherLatestGlucoseValues")!
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "minutes", value: "1440"),
            URLQueryItem(name: "maxCount", value: "1")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data()
        request.timeoutInterval = 30

        print("[Dexcom] Fetching glucose readings...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DexcomError.invalidResponse
        }

        let responseString = String(data: data, encoding: .utf8) ?? ""
        print("[Dexcom] Glucose response (\(httpResponse.statusCode)): \(responseString.prefix(200))")

        if httpResponse.statusCode == 500 {
            if responseString.contains("SessionIdNotFound") || responseString.contains("SessionNotValid") {
                throw DexcomError.sessionExpired
            }
        }

        guard httpResponse.statusCode == 200 else {
            throw DexcomError.invalidResponse
        }

        let decoder = JSONDecoder()
        let readings = try decoder.decode([DexcomGlucoseResponse].self, from: data)

        print("[Dexcom] Got \(readings.count) reading(s)")

        guard let latestRaw = readings.first,
              let reading = latestRaw.toGlucoseReading() else {
            throw DexcomError.noReadingsAvailable
        }

        print("[Dexcom] Latest: \(reading.value) mg/dL \(reading.trendArrow)")
        return reading
    }
}
