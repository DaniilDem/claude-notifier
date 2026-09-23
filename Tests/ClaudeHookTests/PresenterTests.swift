import Testing
@testable import ClaudeHook

let questionJSON = #"{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/p/app","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Какой цвет?","header":"Цвет","multiSelect":false,"options":[{"label":"Красный","description":"a"},{"label":"Синий","description":"b"}]}]}}"#

@Test func stopShowsPromptAndAnswer() throws {
    let input = try parse(#"{"hook_event_name":"Stop","session_id":"s1","cwd":"/p/app","last_assistant_message":"Готово, тесты зелёные."}"#)
    let spec = try #require(Presenter.spec(for: input, lastUserPrompt: "почини тесты\nподробнее"))
    #expect(spec.kind == .info)
    #expect(spec.title == "Done · app")
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
    #expect(spec.title == "Allow? · app")
    #expect(spec.subtitle == "Bash")
    #expect(spec.message == "rm -rf build")
    #expect(spec.actions == ["Allow"])
    #expect(spec.closeLabel == "Deny")
    #expect(spec.timeout == 45)
    #expect(spec.blocking)
    #expect(spec.group == nil)
}

@Test func permissionFallsBackToJSON() throws {
    let input = try parse(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"mcp__x","tool_input":{"foo":"bar"}}"#)
    #expect(Presenter.spec(for: input, lastUserPrompt: nil)?.message == #"{"foo":"bar"}"#)
}

@Test func permissionForAskUserQuestionIsIgnored() throws {
    let input = try parse(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"AskUserQuestion","tool_input":{"questions":[]}}"#)
    #expect(Presenter.spec(for: input, lastUserPrompt: nil) == nil)
}

@Test func permissionWithLongDescriptionFallsBackToInfo() throws {
    let longCommand = String(repeating: "a", count: 300)
    let input = try parse(#"{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/p/app","tool_name":"Bash","tool_input":{"command":"\#(longCommand)"}}"#)
    let spec = try #require(Presenter.spec(for: input, lastUserPrompt: nil))
    #expect(spec.kind == .info)
    #expect(spec.title == "Permission needed · app")
    #expect(spec.subtitle == "Bash")
    #expect(spec.sound == "Ping")
    #expect(spec.group == "claude-s1")
    #expect(!spec.blocking)
}

@Test func questionShowsOptions() throws {
    let spec = try #require(Presenter.spec(for: try parse(questionJSON), lastUserPrompt: nil))
    #expect(spec.kind == .question("Какой цвет?"))
    #expect(spec.subtitle == "Цвет")
    #expect(spec.actions == ["Красный", "Синий"])
    #expect(spec.dropdownLabel == "Answer")
    #expect(spec.closeLabel == "Later")
    #expect(spec.blocking)
}

@Test func questionWithLaterOptionFallsBackToInfo() throws {
    let json = #"{"hook_event_name":"PreToolUse","session_id":"s","cwd":"/p/app","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"When?","options":[{"label":"Now"},{"label":"Later"}]}]}}"#
    let spec = try #require(Presenter.spec(for: try parse(json), lastUserPrompt: nil))
    #expect(spec.kind == .info)
}

@Test func multiQuestionFallsBackToInfo() throws {
    let input = try parse(#"{"hook_event_name":"PreToolUse","session_id":"s","cwd":"/p/app","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"A?","options":[{"label":"x"}]},{"question":"B?","options":[{"label":"y"}]}]}}"#)
    let spec = try #require(Presenter.spec(for: input, lastUserPrompt: nil))
    #expect(spec.kind == .info)
    #expect(spec.title == "Question · app")
    #expect(spec.message == "A?")
}

@Test func ignoresOtherEvents() throws {
    #expect(Presenter.spec(for: try parse(#"{"hook_event_name":"SessionStart","session_id":"s"}"#), lastUserPrompt: nil) == nil)
    #expect(Presenter.spec(for: try parse(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash"}"#), lastUserPrompt: nil) == nil)
}
