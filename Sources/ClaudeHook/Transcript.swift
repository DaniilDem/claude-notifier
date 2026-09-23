import Foundation

public enum Transcript {
    /// Последний текстовый запрос пользователя из JSONL-транскрипта Claude Code.
    /// Пропускает tool_result, служебные (isMeta) записи и вставки вида `<ide_selection>`.
    public static func lastUserPrompt(jsonl: String) -> String? {
        let decoder = JSONDecoder()
        // "\n", а не isNewline: U+2028 может стоять внутри JSON-строки без экранирования.
        for line in jsonl.split(separator: "\n").reversed() {
            guard let entry = try? decoder.decode(JSONValue.self, from: Data(line.utf8)),
                  entry["type"] == .string("user"),
                  entry["isMeta"] != .bool(true),
                  let content = entry["message"]?["content"],
                  let text = promptText(content) else { continue }
            return text
        }
        return nil
    }

    private static func promptText(_ content: JSONValue) -> String? {
        let texts: [String]
        switch content {
        case .string(let text):
            texts = [text]
        case .array(let items):
            texts = items.compactMap { $0["type"] == .string("text") ? $0["text"]?.stringValue : nil }
        default:
            return nil
        }
        return texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("<") }
    }
}
