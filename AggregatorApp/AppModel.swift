import Foundation
import Security
import SwiftUI

private enum SecureStore {
    private static let service = "aggregator-ios"

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "无法保存到钥匙串（错误代码 \(status)）。" }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var owner: String
    @Published var repository: String
    @Published var branch: String
    @Published var token: String
    @Published var subscriptionURL: String
    @Published var runs: [WorkflowRun] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    init() {
        let defaults = UserDefaults.standard
        owner = defaults.string(forKey: "owner") ?? ""
        repository = defaults.string(forKey: "repository") ?? "aggregator"
        branch = defaults.string(forKey: "branch") ?? "main"
        token = SecureStore.read("github-token") ?? ""
        subscriptionURL = SecureStore.read("subscription-url") ?? ""
    }

    func saveSettings() throws {
        let cleanOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRepository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURL.isEmpty {
            guard let url = URL(string: cleanURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                throw SettingsError.invalidSubscriptionURL
            }
        }
        try SecureStore.write(cleanToken, key: "github-token")
        try SecureStore.write(cleanURL, key: "subscription-url")
        let defaults = UserDefaults.standard
        defaults.set(cleanOwner, forKey: "owner")
        defaults.set(cleanRepository, forKey: "repository")
        defaults.set(cleanBranch, forKey: "branch")
        owner = cleanOwner
        repository = cleanRepository
        branch = cleanBranch
        token = cleanToken
        subscriptionURL = cleanURL
    }

    private var client: GitHubClient {
        GitHubClient(owner: owner.trimmingCharacters(in: .whitespacesAndNewlines),
                     repository: repository.trimmingCharacters(in: .whitespacesAndNewlines),
                     branch: branch.trimmingCharacters(in: .whitespacesAndNewlines),
                     token: token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { runs = try await client.runs() }
        catch { errorMessage = error.localizedDescription }
    }

    func dispatch(_ workflow: Workflow) async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.dispatch(workflow)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private enum SettingsError: LocalizedError {
    case invalidSubscriptionURL
    var errorDescription: String? { "订阅链接必须是有效的 HTTP 或 HTTPS 地址。" }
}
