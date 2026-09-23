# claude-notifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Подкоманда `alerter hook` для хуков Claude Code: уведомление с контекстом задачи, клик открывает чат в VS Code, кнопки Allow/Deny и варианты ответа на AskUserQuestion.

**Architecture:** Вся логика «что показать и что ответить Claude» — в новой чистой библиотеке `ClaudeHook` (без AppKit, покрыта тестами). Исполняемый `alerter` получает тонкий `HookRunner`: читает stdin, показывает уведомление через существующий `NotificationManager`, печатает ответ хука. Неблокирующие события (Stop, Notification) уходят в фоновую копию процесса, чтобы Claude не ждал.

**Tech Stack:** Swift 6.2 / SwiftPM, AppKit + NSUserNotification (как в alerter), Swift Testing.

Спецификация: `docs/superpowers/specs/2026-09-23-claude-notifier-design.md`.

## Файлы

| Файл | Что делает |
|---|---|
| `Package.swift` | + library `ClaudeHook`, + test target `ClaudeHookTests` |
| `Sources/ClaudeHook/JSONValue.swift` | типизированное JSON-значение (без `Any` и кастов) |
| `Sources/ClaudeHook/HookInput.swift` | разбор stdin хука |
| `Sources/ClaudeHook/Transcript.swift` | последний запрос пользователя из JSONL-транскрипта |
| `Sources/ClaudeHook/Presenter.swift` | `NotificationSpec` + что показать для события |
| `Sources/ClaudeHook/HookResponse.swift` | что вернуть Claude по нажатой кнопке |
| `Tests/ClaudeHookTests/*.swift` | тесты библиотеки |
| `Sources/Alerter/NotificationManager.swift` | + колбэк `onResult` вместо печати |
| `Sources/Alerter/HookRunner.swift` | режим `hook`: stdin → уведомление → stdout / открыть чат |
| `Sources/Alerter/main.swift` | маршрут `alerter hook ...` → `HookRunner` |
| `docs/claude-hook-samples/*.json` | примеры входа для ручной проверки |

---

### Task 1: Эксперимент — принимает ли Claude ответ AskUserQuestion из хука

Результат решает, остаются ли в Task 5 кнопки вариантов. Код репозитория не меняется.

**Files:**
- Create (временно): `/tmp/ask-spike.sh`
- Modify (временно): `~/.claude/settings.json`

- [ ] **Step 1: Скрипт-заглушка, отвечающий первым вариантом**

```bash
cat > /tmp/ask-spike.sh <<'EOF'
#!/bin/bash
input=$(cat)
printf '%s' "$input" > /tmp/ask-spike-input.json
/usr/bin/jq -c '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:(.tool_input + {answers:{(.tool_input.questions[0].question): .tool_input.questions[0].options[0].label}})}}' <<<"$input"
EOF
chmod +x /tmp/ask-spike.sh
```

- [ ] **Step 2: Бэкап настроек и временный хук**

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak-spike
python3 - <<'EOF'
import json, pathlib
p = pathlib.Path.home() / ".claude/settings.json"
d = json.loads(p.read_text())
d["hooks"].setdefault("PreToolUse", []).append(
    {"matcher": "AskUserQuestion", "hooks": [{"type": "command", "command": "/tmp/ask-spike.sh", "timeout": 10}]})
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
EOF
```

- [ ] **Step 3: Вызвать AskUserQuestion**

Сначала в текущей сессии (если хуки перечитываются на лету), иначе — попросить пользователя открыть новый чат в VS Code и написать: «Задай мне через AskUserQuestion вопрос "Какой цвет?" с вариантами Красный и Синий».

Ожидаемо при успехе: окно вопроса не появляется, Claude получает ответ «Красный». `/tmp/ask-spike-input.json` содержит `tool_input.questions`.

- [ ] **Step 4: Записать результат и вернуть настройки**

```bash
mv ~/.claude/settings.json.bak-spike ~/.claude/settings.json
rm /tmp/ask-spike.sh
```

Если ответ **не** принят — в Task 5 применить вариант «Fallback» (он описан там). Сообщить пользователю результат.

---

### Task 2: Библиотека ClaudeHook — JSONValue и HookInput

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ClaudeHook/JSONValue.swift`, `Sources/ClaudeHook/HookInput.swift`
- Test: `Tests/ClaudeHookTests/HookInputTests.swift`

- [ ] **Step 1: Цели в Package.swift**

В `targets:` добавить перед `.executableTarget(`:

```swift
        .target(
            name: "ClaudeHook",
            path: "Sources/ClaudeHook"
        ),
        .testTarget(
            name: "ClaudeHookTests",
            dependencies: ["ClaudeHook"],
            path: "Tests/ClaudeHookTests"
        ),
```

и в `dependencies` исполняемого `alerter` добавить `"ClaudeHook",` после `"BundleHook",`.

- [ ] **Step 2: Падающий тест**

`Tests/ClaudeHookTests/HookInputTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeHook

func parse(_ json: String) throws -> HookInput {
    try #require(HookInput.parse(Data(json.utf8)))
}

@Test func parsesStopPayload() throws {
    let input = try parse(#"{"hook_event_name":"Stop","session_id":"s1","cwd":"/p/app","last_assistant_message":"Done."}"#)
    #expect(input.hookEventName == "Stop")
    #expect(input.sessionId == "s1")
    #expect(input.lastAssistantMessage == "Done.")
    #expect(!input.isInteractiveEvent)
}

@Test func keepsToolInputTyped() throws {
    let input = try parse(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"npm test","timeout":5,"run_in_background":false}}"#)
    #expect(input.toolInput?["command"]?.stringValue == "npm test")
    #expect(input.toolInput?["timeout"] == .number(5))
    #expect(input.toolInput?["run_in_background"] == .bool(false))
    #expect(input.isInteractiveEvent)
}

@Test func rejectsGarbage() {
    #expect(HookInput.parse(Data("nope".utf8)) == nil)
}
```

- [ ] **Step 3: Запустить — должен упасть**

Run: `swift test --filter HookInputTests`
Expected: ошибка компиляции «cannot find 'HookInput' in scope» (или отсутствие каталога `Sources/ClaudeHook`).

- [ ] **Step 4: Реализация**

`Sources/ClaudeHook/JSONValue.swift`:

```swift
import Foundation

/// JSON-значение без `Any`: tool_input хука нужно прочитать и вернуть обратно с изменениями.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Компактный JSON с отсортированными ключами.
    public var encoded: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
```

`Sources/ClaudeHook/HookInput.swift`:

```swift
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
    public var isInteractiveEvent: Bool {
        hookEventName == "PermissionRequest" || hookEventName == "PreToolUse"
    }
}
```

- [ ] **Step 5: Тесты проходят**

Run: `swift test --filter HookInputTests`
Expected: `3 tests passed`.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ClaudeHook Tests/ClaudeHookTests
git commit -m "Add ClaudeHook library: typed hook input parsing"
```

---

### Task 3: Transcript — последний запрос пользователя

**Files:**
- Create: `Sources/ClaudeHook/Transcript.swift`
- Test: `Tests/ClaudeHookTests/TranscriptTests.swift`

- [ ] **Step 1: Падающий тест**

```swift
import Testing
@testable import ClaudeHook

@Test func lastUserPromptSkipsToolResultsMetaAndTags() {
    let jsonl = """
    {"type":"user","message":{"role":"user","content":"первый запрос"}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}
    {"type":"user","message":{"role":"user","content":[{"type":"text","text":"<ide_selection>x</ide_selection>"},{"type":"text","text":"почини тесты\\nподробнее"}]}}
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"out"}]}}
    {"type":"user","isMeta":true,"message":{"role":"user","content":"meta"}}
    """
    #expect(Transcript.lastUserPrompt(jsonl: jsonl) == "почини тесты\nподробнее")
}

@Test func lastUserPromptNilWhenAbsent() {
    #expect(Transcript.lastUserPrompt(jsonl: "") == nil)
    #expect(Transcript.lastUserPrompt(jsonl: "not json") == nil)
}
```

- [ ] **Step 2: Запустить — падает**

Run: `swift test --filter TranscriptTests`
Expected: «cannot find 'Transcript' in scope».

- [ ] **Step 3: Реализация**

`Sources/ClaudeHook/Transcript.swift`:

```swift
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
```

- [ ] **Step 4: Тесты проходят**

Run: `swift test --filter TranscriptTests`
Expected: `2 tests passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeHook/Transcript.swift Tests/ClaudeHookTests/TranscriptTests.swift
git commit -m "Extract last user prompt from Claude Code transcript"
```

---

### Task 4: Presenter — что показать

**Files:**
- Create: `Sources/ClaudeHook/Presenter.swift`
- Test: `Tests/ClaudeHookTests/PresenterTests.swift`

- [ ] **Step 1: Падающий тест**

```swift
import Testing
@testable import ClaudeHook

let questionJSON = #"{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/p/app","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Какой цвет?","header":"Цвет","multiSelect":false,"options":[{"label":"Красный","description":"a"},{"label":"Синий","description":"b"}]}]}}"#

@Test func stopShowsPromptAndAnswer() throws {
    let input = try parse(#"{"hook_event_name":"Stop","session_id":"s1","cwd":"/p/app","last_assistant_message":"Готово, тесты зелёные."}"#)
    let spec = try #require(Presenter.spec(for: input, lastUserPrompt: "почини тесты\nподробнее"))
    #expect(spec.kind == .info)
    #expect(spec.title == "Готово · app")
    #expect(spec.subtitle == "почини тесты")
    #expect(spec.message == "Готово, тесты зелёные.")
    #expect(spec.sound == "Glass")
    #expect(spec.group == "claude-s1")
    #expect(!spec.blocking)
}

@Test func truncatesTo200() {
    #expect(Presenter.truncate(String(repeating: "a", count: 300)).count == 200)
    #expect(Presenter.truncate("  short  ") == "short")
}

@Test func permissionShowsCommandWithAllowDeny() throws {
    let input = try parse(#"{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/p/app","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}"#)
    let spec = try #require(Presenter.spec(for: input, lastUserPrompt: nil))
    #expect(spec.kind == .permission)
    #expect(spec.title == "Разрешить? · app")
    #expect(spec.subtitle == "Bash")
    #expect(spec.message == "rm -rf build")
    #expect(spec.actions == ["Allow"])
    #expect(spec.closeLabel == "Deny")
    #expect(spec.timeout == 45)
    #expect(spec.blocking)
}

@Test func permissionFallsBackToJSON() throws {
    let input = try parse(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"mcp__x","tool_input":{"foo":"bar"}}"#)
    #expect(Presenter.spec(for: input, lastUserPrompt: nil)?.message == #"{"foo":"bar"}"#)
}

@Test func questionShowsOptions() throws {
    let spec = try #require(Presenter.spec(for: try parse(questionJSON), lastUserPrompt: nil))
    #expect(spec.kind == .question("Какой цвет?"))
    #expect(spec.subtitle == "Цвет")
    #expect(spec.actions == ["Красный", "Синий"])
    #expect(spec.dropdownLabel == "Ответить")
    #expect(spec.closeLabel == "Позже")
    #expect(spec.blocking)
}

@Test func multiQuestionFallsBackToInfo() throws {
    let input = try parse(#"{"hook_event_name":"PreToolUse","session_id":"s","cwd":"/p/app","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"A?","options":[{"label":"x"}]},{"question":"B?","options":[{"label":"y"}]}]}}"#)
    let spec = try #require(Presenter.spec(for: input, lastUserPrompt: nil))
    #expect(spec.kind == .info)
    #expect(spec.title == "Вопрос · app")
    #expect(spec.message == "A?")
}

@Test func ignoresOtherEvents() throws {
    #expect(Presenter.spec(for: try parse(#"{"hook_event_name":"SessionStart","session_id":"s"}"#), lastUserPrompt: nil) == nil)
    #expect(Presenter.spec(for: try parse(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash"}"#), lastUserPrompt: nil) == nil)
}
```

- [ ] **Step 2: Запустить — падает**

Run: `swift test --filter PresenterTests`
Expected: «cannot find 'Presenter' in scope».

- [ ] **Step 3: Реализация**

`Sources/ClaudeHook/Presenter.swift`:

```swift
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
    public var group: String

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
        case "PermissionRequest":
            return NotificationSpec(kind: .permission, title: "Разрешить? · \(project)",
                                    subtitle: input.toolName,
                                    message: truncate(describe(input.toolInput)),
                                    actions: [allow], closeLabel: deny,
                                    sound: "Ping", timeout: blockingTimeout, group: group)
        case "PreToolUse" where input.toolName == "AskUserQuestion":
            return questionSpec(input.toolInput, project: project, group: group)
        default:
            return nil
        }
    }

    /// Один вопрос с одиночным выбором — кнопки. Иначе — просто уведомление.
    private static func questionSpec(_ toolInput: JSONValue?, project: String, group: String) -> NotificationSpec {
        let title = "Вопрос · \(project)"
        guard case .array(let questions)? = toolInput?["questions"], questions.count == 1,
              let question = questions.first,
              let text = question["question"]?.stringValue,
              question["multiSelect"] != .bool(true),
              case .array(let options)? = question["options"],
              case let labels = options.compactMap({ $0["label"]?.stringValue }), !labels.isEmpty else {
            var text = "Claude задаёт вопрос"
            if case .array(let questions)? = toolInput?["questions"],
               let first = questions.first?["question"]?.stringValue {
                text = first
            }
            return NotificationSpec(kind: .info, title: title, message: truncate(text),
                                    sound: "Ping", timeout: infoTimeout, group: group)
        }
        return NotificationSpec(kind: .question(text), title: title,
                                subtitle: question["header"]?.stringValue,
                                message: truncate(text),
                                actions: labels, dropdownLabel: "Ответить", closeLabel: later,
                                sound: "Ping", timeout: blockingTimeout, group: group)
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
```

- [ ] **Step 4: Тесты проходят**

Run: `swift test --filter PresenterTests`
Expected: `7 tests passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeHook/Presenter.swift Tests/ClaudeHookTests/PresenterTests.swift
git commit -m "Map Claude Code hook events to notification specs"
```

---

### Task 5: HookResponse — ответ Claude

**Files:**
- Create: `Sources/ClaudeHook/HookResponse.swift`
- Test: `Tests/ClaudeHookTests/HookResponseTests.swift`

- [ ] **Step 1: Падающий тест**

```swift
import Foundation
import Testing
@testable import ClaudeHook

private let permissionJSON = #"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}"#

@Test func permissionAllowAndDeny() throws {
    let input = try parse(permissionJSON)
    let spec = try #require(Presenter.spec(for: input, lastUserPrompt: nil))
    #expect(HookResponse.json(for: spec, input: input, chosen: "Allow")
            == #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
    #expect(HookResponse.json(for: spec, input: input, chosen: "Deny")
            == #"{"hookSpecificOutput":{"decision":{"behavior":"deny"},"hookEventName":"PermissionRequest"}}"#)
    #expect(HookResponse.json(for: spec, input: input, chosen: "other") == nil)
}

@Test func questionAnswerGoesToUpdatedInput() throws {
    let input = try parse(questionJSON)
    let spec = try #require(Presenter.spec(for: input, lastUserPrompt: nil))
    let out = try #require(HookResponse.json(for: spec, input: input, chosen: "Синий"))
    let output = try JSONDecoder().decode(JSONValue.self, from: Data(out.utf8))["hookSpecificOutput"]
    #expect(output?["hookEventName"] == .string("PreToolUse"))
    #expect(output?["permissionDecision"] == .string("allow"))
    #expect(output?["updatedInput"]?["answers"]?["Какой цвет?"] == .string("Синий"))
    #expect(output?["updatedInput"]?["questions"] != nil)
}

@Test func laterAndInfoGiveNoOutput() throws {
    let question = try parse(questionJSON)
    let questionSpec = try #require(Presenter.spec(for: question, lastUserPrompt: nil))
    #expect(HookResponse.json(for: questionSpec, input: question, chosen: "Позже") == nil)

    let stop = try parse(#"{"hook_event_name":"Stop","session_id":"s"}"#)
    let stopSpec = try #require(Presenter.spec(for: stop, lastUserPrompt: nil))
    #expect(HookResponse.json(for: stopSpec, input: stop, chosen: "Allow") == nil)
}
```

- [ ] **Step 2: Запустить — падает**

Run: `swift test --filter HookResponseTests`
Expected: «cannot find 'HookResponse' in scope».

- [ ] **Step 3: Реализация**

`Sources/ClaudeHook/HookResponse.swift`:

```swift
/// JSON для stdout хука по нажатой кнопке. nil — решения нет, Claude спросит сам.
public enum HookResponse {
    public static func json(for spec: NotificationSpec, input: HookInput, chosen: String) -> String? {
        switch spec.kind {
        case .info:
            return nil
        case .permission:
            let behavior: String
            switch chosen {
            case Presenter.allow: behavior = "allow"
            case Presenter.deny: behavior = "deny"
            default: return nil
            }
            return JSONValue.object(["hookSpecificOutput": .object([
                "hookEventName": .string("PermissionRequest"),
                "decision": .object(["behavior": .string(behavior)]),
            ])]).encoded
        case .question(let question):
            guard spec.actions.contains(chosen), case .object(var updated)? = input.toolInput else { return nil }
            updated["answers"] = .object([question: .string(chosen)])
            return JSONValue.object(["hookSpecificOutput": .object([
                "hookEventName": .string("PreToolUse"),
                "permissionDecision": .string("allow"),
                "updatedInput": .object(updated),
            ])]).encoded
        }
    }
}
```

**Fallback (только если Task 1 показал, что `answers` не принимаются):** в `Presenter.questionSpec` заменить весь `guard ... else { ... }` + финальный `return` на ветку «просто уведомление»:

```swift
    private static func questionSpec(_ toolInput: JSONValue?, project: String, group: String) -> NotificationSpec {
        var text = "Claude задаёт вопрос"
        if case .array(let questions)? = toolInput?["questions"],
           let first = questions.first?["question"]?.stringValue {
            text = first
        }
        return NotificationSpec(kind: .info, title: "Вопрос · \(project)", message: truncate(text),
                                sound: "Ping", timeout: infoTimeout, group: group)
    }
```

и удалить тесты `questionShowsOptions`, `questionAnswerGoesToUpdatedInput`, первую половину `laterAndInfoGiveNoOutput`; в `multiQuestionFallsBackToInfo` ничего не менять.

- [ ] **Step 4: Все тесты проходят**

Run: `swift test`
Expected: все тесты `passed`, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeHook/HookResponse.swift Tests/ClaudeHookTests/HookResponseTests.swift
git commit -m "Build hook decision output from notification clicks"
```

---

### Task 6: HookRunner — режим `alerter hook`

UI-код, автотестов нет (как во всём alerter); проверка — сборка + ручной прогон в Task 7.

**Files:**
- Modify: `Sources/Alerter/NotificationManager.swift` (свойства класса и `outputAndExit`)
- Create: `Sources/Alerter/HookRunner.swift`
- Modify: `Sources/Alerter/main.swift`

- [ ] **Step 1: Колбэк в NotificationManager**

После `private var hasExited = false` добавить:

```swift
    /// Если задан, получает результат вместо печати в stdout (режим `hook`).
    var onResult: ((ActivationEvent) -> Void)?
```

`outputAndExit` заменить на:

```swift
    private func outputAndExit(event: ActivationEvent) {
        guard !hasExited else { return }
        hasExited = true
        if let onResult {
            onResult(event)
        } else {
            let output = OutputFormatter.format(event: event, asJSON: currentConfig?.outputJSON ?? false)
            print(output, terminator: "")
        }
        exit(0)
    }
```

- [ ] **Step 2: HookRunner**

`Sources/Alerter/HookRunner.swift`:

```swift
import AppKit
import BundleHook
import ClaudeHook

/// `alerter hook` — уведомления для хуков Claude Code. См. docs/superpowers/specs/2026-09-23-claude-notifier-design.md.
enum HookRunner {
    static let vscodeBundleID = "com.microsoft.VSCode"
    static let claudeBundleID = "com.anthropic.claudefordesktop"

    static func run(arguments: [String]) -> Never {
        // Фоновая копия для неблокирующих событий: payload во временном файле.
        if arguments.count == 2, arguments[0] == "--payload" {
            let file = URL(fileURLWithPath: arguments[1])
            let data = try? Data(contentsOf: file)
            try? FileManager.default.removeItem(at: file)
            guard let data, let input = HookInput.parse(data) else { exit(0) }
            present(input)
        }

        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let input = HookInput.parse(data) else { exit(0) }
        if input.isInteractiveEvent,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == vscodeBundleID {
            exit(0) // пользователь смотрит на VS Code — пусть ответит там
        }
        guard let spec = Presenter.spec(for: input, lastUserPrompt: nil) else { exit(0) }
        if spec.blocking {
            present(input)
        }
        spawnBackground(payload: data)
        exit(0)
    }

    private static func present(_ input: HookInput) -> Never {
        let prompt = input.transcriptPath
            .flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            .flatMap(Transcript.lastUserPrompt(jsonl:))
        guard let spec = Presenter.spec(for: input, lastUserPrompt: prompt) else { exit(0) }

        let hasClaudeApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeBundleID) != nil
        _ = InstallFakeBundleIdentifierHook(hasClaudeApp ? claudeBundleID : vscodeBundleID)

        let manager = NotificationManager.shared
        manager.onResult = { event in handle(event, spec: spec, input: input) }
        manager.deliverNotification(config: NotificationConfig(
            title: spec.title,
            subtitle: spec.subtitle,
            message: spec.message,
            closeLabel: spec.closeLabel,
            actions: spec.actions.isEmpty ? nil : spec.actions,
            dropdownLabel: spec.dropdownLabel,
            replyPlaceholder: nil,
            sound: spec.sound,
            groupID: spec.group,
            appIcon: nil,
            contentImage: nil,
            timeout: spec.timeout,
            outputJSON: false,
            ignoreDnD: false,
            uuid: UUID().uuidString
        ))
        NSApplication.shared.run()
        exit(0)
    }

    private static func handle(_ event: ActivationEvent, spec: NotificationSpec, input: HookInput) {
        switch event.type {
        case .contentsClicked:
            openChat(sessionId: input.sessionId)
        case .actionClicked, .closed:
            if let chosen = event.value, let json = HookResponse.json(for: spec, input: input, chosen: chosen) {
                print(json)
            }
        case .timeout, .replied, .none:
            break
        }
    }

    /// Обработчик `/open` расширения Claude Code для VS Code.
    private static func openChat(sessionId: String) {
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = "anthropic.claude-code"
        components.path = "/open"
        components.queryItems = [URLQueryItem(name: "session", value: sessionId)]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private static func spawnBackground(payload: Data) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-notifier-\(UUID().uuidString).json")
        guard (try? payload.write(to: file)) != nil,
              let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["hook", "--payload", file.path]
        // Не наследуем пайпы хука: иначе Claude Code ждал бы, пока фоновая копия завершится.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
```

- [ ] **Step 3: Маршрут в main.swift**

Перед `AlerterCommand.main()`:

```swift
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "hook" {
    HookRunner.run(arguments: Array(arguments.dropFirst()))
}
```

- [ ] **Step 4: Сборка и тесты**

Run: `swift build && swift test`
Expected: `Build complete!`, все тесты passed.

- [ ] **Step 5: Быстрая проверка без UI**

```bash
echo 'garbage' | .build/debug/alerter hook; echo "exit=$?"
echo '{"hook_event_name":"SessionStart","session_id":"s"}' | .build/debug/alerter hook; echo "exit=$?"
.build/debug/alerter --message "старый режим" --timeout 2; echo " exit=$?"
```

Expected: первые два — пустой вывод и `exit=0`; третий — уведомление, через 2 с `@TIMEOUT exit=0`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Alerter
git commit -m "Add 'alerter hook' mode for Claude Code hooks"
```

---

### Task 7: Примеры входа и ручная проверка

**Files:**
- Create: `docs/claude-hook-samples/stop.json`, `permission.json`, `question.json`, `notification.json`

- [ ] **Step 1: Примеры**

```bash
mkdir -p docs/claude-hook-samples
cat > docs/claude-hook-samples/stop.json <<'EOF'
{"hook_event_name":"Stop","session_id":"00000000-0000-0000-0000-000000000000","cwd":"/Users/me/projects/app","last_assistant_message":"Готово: тесты зелёные, PR создан."}
EOF
cat > docs/claude-hook-samples/notification.json <<'EOF'
{"hook_event_name":"Notification","session_id":"00000000-0000-0000-0000-000000000000","cwd":"/Users/me/projects/app","message":"Claude is waiting for your input"}
EOF
cat > docs/claude-hook-samples/permission.json <<'EOF'
{"hook_event_name":"PermissionRequest","session_id":"00000000-0000-0000-0000-000000000000","cwd":"/Users/me/projects/app","tool_name":"Bash","tool_input":{"command":"npm test"}}
EOF
cat > docs/claude-hook-samples/question.json <<'EOF'
{"hook_event_name":"PreToolUse","session_id":"00000000-0000-0000-0000-000000000000","cwd":"/Users/me/projects/app","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Какой цвет?","header":"Цвет","multiSelect":false,"options":[{"label":"Красный","description":"a"},{"label":"Синий","description":"b"}]}]}}
EOF
```

- [ ] **Step 2: Неблокирующие**

```bash
.build/debug/alerter hook < docs/claude-hook-samples/stop.json; echo "exit=$?"
```

Expected: мгновенно `exit=0`; появляется уведомление «Готово · app» от Claude; `pgrep -fl 'alerter hook --payload'` показывает фоновую копию.

- [ ] **Step 3: Блокирующие (нужен пользователь: VS Code не должен быть активным)**

```bash
sleep 5; .build/debug/alerter hook < docs/claude-hook-samples/permission.json; echo " exit=$?"
```

Пользователь за 5 с переключается в другое приложение, затем жмёт Allow.
Expected: `{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}} exit=0`. Повторить с Deny, смахиванием (→ deny) и бездействием 45 с (→ пусто).
Аналогично `question.json`: выбор «Синий» → JSON с `answers`; «Позже» → пусто.

- [ ] **Step 4: Commit**

```bash
git add docs/claude-hook-samples
git commit -m "Add sample hook payloads for manual testing"
```

---

### Task 8: Установка и живая проверка

**Files:**
- Modify: `~/.claude/settings.json`
- Create: `~/.claude/hooks/claude-notifier`
- Delete: `~/.claude/hooks/claude-notify.sh`

- [ ] **Step 1: Release-сборка и копия**

```bash
swift build -c release && cp .build/release/alerter ~/.claude/hooks/claude-notifier
```

- [ ] **Step 2: Хуки в settings.json (с бэкапом)**

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak-claude-notifier
python3 - <<'EOF'
import json, pathlib
p = pathlib.Path.home() / ".claude/settings.json"
d = json.loads(p.read_text())
h = d["hooks"]
cmd = '"$HOME/.claude/hooks/claude-notifier" hook'
def ours(timeout):
    return {"type": "command", "command": cmd, "timeout": timeout}
# убрать старый claude-notify.sh и прошлые установки claude-notifier (подстрока покрывает оба)
for event in ["Stop", "Notification", "PermissionRequest", "PreToolUse"]:
    h[event] = [g for g in h.get(event, []) if not any("claude-notif" in x.get("command", "") for x in g["hooks"])]
h["Stop"].append({"hooks": [ours(10)]})
h["Notification"].append({"matcher": "idle_prompt|elicitation_dialog", "hooks": [ours(10)]})
h["PermissionRequest"].append({"hooks": [ours(60)]})
h["PreToolUse"].append({"matcher": "AskUserQuestion", "hooks": [ours(60)]})
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
EOF
python3 -c "import json;json.load(open('$HOME/.claude/settings.json'))" && echo valid
rm ~/.claude/hooks/claude-notify.sh
```

Expected: `valid`.

- [ ] **Step 3: Стиль уведомлений Claude.app**

Пользователь: System Settings → Notifications → Claude → стиль «Alerts» (иначе баннер с кнопками исчезает через ~5 с).

- [ ] **Step 4: Живая проверка в новом чате VS Code**

1. Переключиться из VS Code, дождаться конца задачи → уведомление «Готово · …» с запросом и ответом; клик → VS Code открывает этот чат.
2. Попросить Claude выполнить Bash-команду, требующую разрешения, и переключиться из VS Code → Allow → команда выполняется без окна в VS Code.
3. То же, но VS Code активен → уведомления нет, обычное окно разрешения.
4. Попросить AskUserQuestion, переключиться → выбрать вариант → Claude продолжает с ответом.
5. После Stop: `pgrep -fl 'claude-notifier hook --payload'` — фоновая копия жива, пока уведомление не закрыто.

Если в п.5 фоновая копия погибает вместе с хуком — заменить `Process` в `spawnBackground` на `posix_spawn` с флагом `POSIX_SPAWN_SETSID` и `/dev/null` для 0/1/2 и повторить.

---

### Task 9: README и публикация форка

**Files:**
- Modify: `README.md` (раздел в начале)

- [ ] **Step 1: Раздел в README**

Вставить сразу после заголовка первого уровня:

```markdown
## Claude Code hook mode (this fork)

`alerter hook` reads a Claude Code hook payload from stdin and shows a notification with the task
context. Clicking it opens the chat in VS Code; permission requests get Allow/Deny buttons and
AskUserQuestion gets its options as buttons. See `docs/superpowers/specs/2026-09-23-claude-notifier-design.md`.

    swift build -c release && cp .build/release/alerter ~/.claude/hooks/claude-notifier

Hooks: `Stop`, `Notification` (`idle_prompt|elicitation_dialog`), `PermissionRequest`,
`PreToolUse` (`AskUserQuestion`) → `"$HOME/.claude/hooks/claude-notifier" hook`.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Document Claude Code hook mode"
```

- [ ] **Step 3: Форк и push (подтвердить у пользователя перед выполнением)**

```bash
gh repo fork vjeantet/alerter --fork-name claude-notifier --clone=false
git remote rename origin upstream
git remote add origin https://github.com/DaniilDem/claude-notifier.git
git push -u origin claude-hook
```

Спросить пользователя: сливать `claude-hook` в `master` форка или открыть PR внутри форка.
