import Foundation
import Security
import LocalAuthentication

public struct Quiz: Codable, Equatable, Sendable {
    public let question: String
    public let choices: [String]
    public let answer: Int
    public let explanation: String
    public init(question: String, choices: [String], answer: Int, explanation: String) { self.question=question; self.choices=choices; self.answer=answer; self.explanation=explanation }
    public func validated() throws -> Quiz {
        guard !question.isEmpty, question.count <= 4000, choices.count == 4, Set(choices).count == 4, choices.allSatisfy({ !$0.isEmpty && $0.count <= 2000 }), (0..<4).contains(answer), !explanation.isEmpty, explanation.count <= 6000 else { throw CoachError.message("The AI returned an invalid question. Please retry.") }
        return self
    }
}
public enum Keychain {
    private static func query(service:String) -> [String:Any] { [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"api-key"] }
    /// Startup checks existence without requesting the secret or displaying a Keychain authorization dialog.
    public static func contains(service:String="com.codecoach.mac.openai") throws -> Bool {
        var q=query(service:service)
        q[kSecMatchLimit as String]=kSecMatchLimitOne
        let context=LAContext();context.interactionNotAllowed=true
        q[kSecUseAuthenticationContext as String]=context
        let status=SecItemCopyMatching(q as CFDictionary,nil)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw CoachError.message(status == errSecInteractionNotAllowed ? "Unlock Keychain, then reopen the app." : "Could not check Keychain credential status (\(status)).")
    }
    public static func read(service:String="com.codecoach.mac.openai") throws -> String? {
        var q=query(service:service); q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne
        var item: CFTypeRef?; let status=SecItemCopyMatching(q as CFDictionary,&item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data=item as? Data else { throw CoachError.message("Could not read Keychain (\(status)). Check system authorization.") }
        return String(data:data,encoding:.utf8)
    }
    public static func save(_ key: String,service:String="com.codecoach.mac.openai") throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query(service:service) as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var q=query(service:service); q[kSecValueData as String]=data; q[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary,nil) == errSecSuccess else { throw CoachError.message("Could not save the API key to Keychain.") }
        } else if status != errSecSuccess { throw CoachError.message("Could not update the API key (\(status)).") }
    }
    public static func delete(service:String="com.codecoach.mac.openai") throws { let s=SecItemDelete(query(service:service) as CFDictionary); guard s == errSecSuccess || s == errSecItemNotFound else { throw CoachError.message("Could not delete the API key (\(s)).") } }
}
public struct QuizClient {
    public var session: URLSession
    public init(session: URLSession? = nil) { self.session = session ?? DatabricksClient(provider:.openai).session }
    public static func preview(_ stats: [TopicStat]) throws -> String { String(decoding: try JSONEncoder().encode(Array(stats.prefix(6))), as: UTF8.self) }
    public func generate(stats: [TopicStat], key: String, model: String) async throws -> Quiz {
        try await DatabricksClient(session:session,provider:.openai).generate(stats:stats,key:key,model:model)
    }
}
