import AppKit
import BundleHook
import ClaudeHook

/// `alerter hook` — уведомления для хуков Claude Code. См. docs/superpowers/specs/2026-09-23-claude-notifier-design.md.
enum HookRunner {
    static let vscodeBundleID = "com.microsoft.VSCode"
    static let terminalNotifier = "/opt/homebrew/bin/terminal-notifier"

    static func run(arguments: [String]) -> Never {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let input = HookInput.parse(data) else { exit(0) }
        if input.isInteractiveEvent,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == vscodeBundleID {
            exit(0) // пользователь смотрит на VS Code — пусть ответит там
        }
        // Транскрипт нужен только для подзаголовка Stop — не читаем его для остальных событий.
        let prompt = input.hookEventName == "Stop"
            ? input.transcriptPath
                .flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
                .flatMap(Transcript.lastUserPrompt(jsonl:))
            : nil
        guard let spec = Presenter.spec(for: input, lastUserPrompt: prompt) else { exit(0) }
        if spec.blocking {
            present(spec, input: input)
        }
        let projectDir = ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? input.cwd
        notifyViaTerminalNotifier(spec, sessionId: input.sessionId, projectDir: projectDir)
        exit(0)
    }

    /// Неблокирующие уведомления показывает terminal-notifier: это отдельное приложение со своими
    /// разрешениями. Подмена отправителя в NSUserNotification на macOS 15 ненадёжна: от имени
    /// VS Code/Terminal баннер не показывается, от имени Claude/terminal-notifier не приходят клики.
    private static func notifyViaTerminalNotifier(_ spec: NotificationSpec, sessionId: String, projectDir: String?) {
        guard FileManager.default.isExecutableFile(atPath: terminalNotifier),
              let url = chatURL(sessionId: sessionId) else { return }
        // vscode:// уходит в последнее активное окно VS Code; в окне с другой папкой сессии нет
        // и расширение создаёт новый чат. Поэтому сначала выводим окно проекта сессии.
        var onClick = "open \(shellQuoted(url.absoluteString))"
        if let projectDir, vscodeHasWindow(forFolder: projectDir) {
            onClick = "open -a 'Visual Studio Code' \(shellQuoted(projectDir)) && sleep 1 && " + onClick
        }
        var arguments = ["-title", spec.title, "-sound", spec.sound, "-execute", onClick]
        if let subtitle = spec.subtitle { arguments += ["-subtitle", subtitle] }
        if let group = spec.group { arguments += ["-group", group] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: terminalNotifier)
        process.arguments = arguments
        // Текст через stdin: аргументы terminal-notifier разбираются как plist, и "(…" или "{…" ломаются.
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        stdin.fileHandleForWriting.write(Data(spec.message.utf8))
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    /// Кнопки ответа (PermissionRequest / AskUserQuestion). В settings.json не подключено:
    /// на macOS 15 баннер от имени VS Code не показывается, пока VS Code активен.
    private static func present(_ spec: NotificationSpec, input: HookInput) -> Never {
        _ = InstallFakeBundleIdentifierHook(vscodeBundleID)

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
            if let url = chatURL(sessionId: input.sessionId) {
                NSWorkspace.shared.open(url)
            }
        case .actionClicked, .closed:
            if let chosen = event.value, let json = HookResponse.json(for: spec, input: input, chosen: chosen) {
                print(json)
            }
        case .timeout, .replied, .none:
            break
        }
    }

    /// Есть ли в VS Code окно с этой папкой (по сохранённому состоянию окон). Без проверки
    /// `open -a` создал бы новое окно — например, для чата из окна без папки (cwd = ~).
    private static func vscodeHasWindow(forFolder folder: String) -> Bool {
        let storage = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/User/globalStorage/storage.json")
        guard let data = try? Data(contentsOf: storage),
              let state = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .array(let windows)? = state["windowsState"]?["openedWindows"] else { return false }
        let target = URL(fileURLWithPath: folder).standardized.path
        return windows.contains { window in
            window["folder"]?.stringValue.flatMap(URL.init(string:))?.standardized.path == target
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Обработчик `/open` расширения Claude Code для VS Code.
    private static func chatURL(sessionId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = "anthropic.claude-code"
        components.path = "/open"
        components.queryItems = [URLQueryItem(name: "session", value: sessionId)]
        return components.url
    }
}
