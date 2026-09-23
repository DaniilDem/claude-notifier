import Foundation

/// Что показать в уведомлении и как на него реагировать.
public struct NotificationSpec: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case info
        case permission
        /// Вопрос AskUserQuestion; текст вопроса — ключ в `answers`.
        case question(String)
    }

    public var kind: Kind
    public var title: String
    public var subtitle: String?
    public var message: String
    public var actions: [String] = []
    public var dropdownLabel: String?
    public var closeLabel: String?
    public var sound: String
    public var timeout: Int
    /// nil для блокирующих спеков (.permission, .question): их нельзя схлопывать с другими
    /// уведомлениями сессии — свайп для закрытия репортится как `.closed` ("Deny"/"Позже").
    public var group: String?

    /// Хук ждёт клика и отвечает Claude через stdout.
    public var blocking: Bool { kind != .info }
}

public enum Presenter {
    public static let allow = "Allow"
    public static let deny = "Deny"
    public static let later = "Позже"
    static let blockingTimeout = 45
    static let infoTimeout = 1800

    public static func spec(for input: HookInput, lastUserPrompt: String?) -> NotificationSpec? {
        let project = input.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude"
        let group = "claude-\(input.sessionId)"

        switch input.hookEventName {
        case "Stop":
            return NotificationSpec(kind: .info, title: "Готово · \(project)",
                                    subtitle: lastUserPrompt.flatMap(firstLine),
                                    message: truncate(input.lastAssistantMessage ?? "Задача завершена"),
                                    sound: "Glass", timeout: infoTimeout, group: group)
        case "Notification":
            return NotificationSpec(kind: .info, title: "Нужен ответ · \(project)",
                                    message: truncate(input.message ?? "Claude ждёт твоего ответа"),
                                    sound: "Ping", timeout: infoTimeout, group: group)
        case "PermissionRequest" where input.toolName != "AskUserQuestion":
            return permissionSpec(input, project: project)
        case "PreToolUse" where input.toolName == "AskUserQuestion":
            return questionSpec(input.toolInput, project: project, session: input.sessionId)
        default:
            return nil
        }
    }

    /// Длинную команду нельзя разрешать не глядя на хвост — просто уведомление вместо Allow/Deny.
    private static func permissionSpec(_ input: HookInput, project: String) -> NotificationSpec {
        let description = describe(input.toolInput)
        guard description.count <= 200 else {
            return NotificationSpec(kind: .info, title: "Нужно разрешение · \(project)",
                                    subtitle: input.toolName,
                                    message: truncate(description),
                                    sound: "Ping", timeout: infoTimeout, group: "claude-\(input.sessionId)")
        }
        return NotificationSpec(kind: .permission, title: "Разрешить? · \(project)",
                                subtitle: input.toolName,
                                message: truncate(description),
                                actions: [allow], closeLabel: deny,
                                sound: "Ping", timeout: blockingTimeout, group: nil)
    }

    /// Один вопрос с одиночным выбором — кнопки. Иначе — просто уведомление.
    private static func questionSpec(_ toolInput: JSONValue?, project: String, session: String) -> NotificationSpec {
        let title = "Вопрос · \(project)"
        guard case .array(let questions)? = toolInput?["questions"], questions.count == 1,
              let question = questions.first,
              let text = question["question"]?.stringValue,
              question["multiSelect"] != .bool(true),
              case .array(let options)? = question["options"],
              case let labels = options.compactMap({ $0["label"]?.stringValue }), !labels.isEmpty,
              // "Позже" — наша кнопка закрытия; если это ещё и вариант ответа, их не различить.
              !labels.contains(later) else {
            var text = "Claude задаёт вопрос"
            if case .array(let questions)? = toolInput?["questions"],
               let first = questions.first?["question"]?.stringValue {
                text = first
            }
            return NotificationSpec(kind: .info, title: title, message: truncate(text),
                                    sound: "Ping", timeout: infoTimeout, group: "claude-\(session)")
        }
        return NotificationSpec(kind: .question(text), title: title,
                                subtitle: question["header"]?.stringValue,
                                message: truncate(text),
                                actions: labels, dropdownLabel: "Ответить", closeLabel: later,
                                sound: "Ping", timeout: blockingTimeout, group: nil)
    }

    static func truncate(_ text: String, limit: Int = 200) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "…" : trimmed
    }

    static func firstLine(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let result = truncate(line, limit: 80)
        return result.isEmpty ? nil : result
    }

    /// Самое информативное поле tool_input, иначе весь tool_input как JSON.
    static func describe(_ toolInput: JSONValue?) -> String {
        for key in ["command", "file_path", "url", "pattern", "prompt"] {
            if let value = toolInput?[key]?.stringValue { return value }
        }
        return toolInput?.encoded ?? ""
    }
}
