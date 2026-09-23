import AppKit

let notificationManager = NotificationManager.shared

signal(SIGTERM) { _ in
    notificationManager.bye()
    exit(EXIT_FAILURE)
}

signal(SIGINT) { _ in
    notificationManager.bye()
    exit(EXIT_FAILURE)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "hook" {
    HookRunner.run(arguments: Array(arguments.dropFirst()))
}

AlerterCommand.main()
