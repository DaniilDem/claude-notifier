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
