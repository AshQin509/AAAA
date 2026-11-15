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
        guard !question.isEmpty, question.count <= 4000, choices.count == 4, Set(choices).count == 4, choices.allSatisfy({ !$0.isEmpty && $0.count <= 2000 }), (0..<4).contains(answer), !explanation.isEmpty, explanation.count <= 6000 else { throw CoachError.message("AI 返回了无效题目，请重试。") }
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
        throw CoachError.message(status == errSecInteractionNotAllowed ? "钥匙串目前需要解锁，解锁后请重新打开应用。" : "无法检查钥匙串凭证状态（\(status)）。")
    }
    public static func read(service:String="com.codecoach.mac.openai") throws -> String? {
        var q=query(service:service); q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne
        var item: CFTypeRef?; let status=SecItemCopyMatching(q as CFDictionary,&item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data=item as? Data else { throw CoachError.message("无法读取钥匙串（\(status)）。请检查系统授权。") }
        return String(data:data,encoding:.utf8)
    }
    public static func save(_ key: String,service:String="com.codecoach.mac.openai") throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query(service:service) as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var q=query(service:service); q[kSecValueData as String]=data; q[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary,nil) == errSecSuccess else { throw CoachError.message("API Key 无法存入钥匙串。") }
        } else if status != errSecSuccess { throw CoachError.message("API Key 无法更新（\(status)）。") }
    }
    public static func delete(service:String="com.codecoach.mac.openai") throws { let s=SecItemDelete(query(service:service) as CFDictionary); guard s == errSecSuccess || s == errSecItemNotFound else { throw CoachError.message("无法删除 API Key（\(s)）。") } }
}
public struct QuizClient {
    public var session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public static func preview(_ stats: [TopicStat]) throws -> String { String(decoding: try JSONEncoder().encode(Array(stats.prefix(6))), as: UTF8.self) }
    public func generate(stats: [TopicStat], key: String, model: String) async throws -> Quiz {
        guard !key.isEmpty, !model.trimmingCharacters(in:.whitespaces).isEmpty else { throw CoachError.message("请先设置 API Key 和模型。") }
        let schema: [String:Any] = ["type":"object","properties":["question":["type":"string"],"choices":["type":"array","items":["type":"string"],"minItems":4,"maxItems":4],"answer":["type":"integer","minimum":0,"maximum":3],"explanation":["type":"string"]],"required":["question","choices","answer","explanation"],"additionalProperties":false]
        let body: [String:Any] = ["model":model,"store":false,"max_output_tokens":2500,"instructions":"你是耐心的 Java 教练。根据匿名知识点频次和练习正确率，生成一道全新的四选一 Java 练习，用简体中文，代码可使用换行。必须围绕输入列表第一个 topic 出题，其他项只作背景；结合该知识点答题正确率调整难度，尚未答题时使用入门难度；不要把编译错误等同于能力判断。answer 是 0-based 正确选项下标，explanation 解释正确和错误选项。只返回指定 JSON。", "input":try Self.preview(stats),"text":["format":["type":"json_schema","name":"java_quiz","strict":true,"schema":schema]]]
        var request=URLRequest(url:URL(string:"https://api.openai.com/v1/responses")!); request.httpMethod="POST"; request.timeoutInterval=60
        request.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization"); request.setValue("application/json",forHTTPHeaderField:"Content-Type"); request.httpBody=try JSONSerialization.data(withJSONObject:body)
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse else { throw CoachError.message("未收到有效 API 响应。") }
        guard http.statusCode == 200 else { throw CoachError.message(http.statusCode == 401 ? "API Key 无效或已过期。" : http.statusCode == 429 ? "API 配额不足或请求过快，请检查账户后重试。" : "OpenAI 请求失败（HTTP \(http.statusCode)）。请检查模型访问权限或稍后重试。") }
        guard data.count <= 200_000, let json=try JSONSerialization.jsonObject(with:data) as? [String:Any], json["status"] as? String == "completed", let output=json["output"] as? [[String:Any]] else { throw CoachError.message("AI 响应未完成，请重试。") }
        let texts=output.flatMap { $0["content"] as? [[String:Any]] ?? [] }.filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }
        guard let text=texts.first else { throw CoachError.message("AI 未能生成题目，可能拒绝了本次请求。") }
        return try JSONDecoder().decode(Quiz.self,from:Data(text.utf8)).validated()
    }
}
