import AppKit
import BundleHook
import ClaudeHook

/// `alerter hook` — уведомления для хуков Claude Code. См. docs/superpowers/specs/2026-09-23-claude-notifier-design.md.
enum HookRunner {
    static let vscodeBundleID = "com.microsoft.VSCode"

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
        // Транскрипт нужен только для подзаголовка Stop — не читаем его для остальных событий.
        let prompt = input.hookEventName == "Stop"
            ? input.transcriptPath
                .flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
                .flatMap(Transcript.lastUserPrompt(jsonl:))
            : nil
        guard let spec = Presenter.spec(for: input, lastUserPrompt: prompt) else { exit(0) }

        // Не Claude.app: с его bundle id NSUserNotificationCenter не присылает делегату
        // ни доставку, ни клики — процесс висит без таймаута (проверено на macOS 15).
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
