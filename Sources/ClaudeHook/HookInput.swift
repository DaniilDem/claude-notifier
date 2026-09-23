import Foundation

/// JSON, который Claude Code передаёт хуку в stdin (нужные нам поля).
public struct HookInput: Decodable, Sendable {
    public let hookEventName: String
    public let sessionId: String
    public let cwd: String?
    public let transcriptPath: String?
    public let lastAssistantMessage: String?
    public let message: String?
    public let toolName: String?
    public let toolInput: JSONValue?

    // Явные ключи: convertFromSnakeCase переименовал бы и ключи внутри tool_input.
    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case cwd
        case transcriptPath = "transcript_path"
        case lastAssistantMessage = "last_assistant_message"
        case message
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }

    public static func parse(_ data: Data) -> HookInput? {
        try? JSONDecoder().decode(HookInput.self, from: data)
    }

    /// События, на которые хук может ответить решением — для них ждём клика.
    /// PreToolUse интерактивен только для AskUserQuestion: остальные PreToolUse — не наш хук.
    public var isInteractiveEvent: Bool {
        hookEventName == "PermissionRequest" || (hookEventName == "PreToolUse" && toolName == "AskUserQuestion")
    }
}
