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
