import Testing
@testable import ClaudeHook

@Test func lastUserPromptSkipsToolResultsMetaAndTags() {
    let jsonl = """
    {"type":"user","message":{"role":"user","content":"первый запрос"}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}
    {"type":"user","message":{"role":"user","content":[{"type":"text","text":"<ide_selection>x</ide_selection>"},{"type":"text","text":"почини тесты\\nподробнее"}]}}
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"out"}]}}
    {"type":"user","isMeta":true,"message":{"role":"user","content":"meta"}}
    {"type":"user","isCompactSummary":true,"message":{"role":"user","content":"summary"}}
    """
    #expect(Transcript.lastUserPrompt(jsonl: jsonl) == "почини тесты\nподробнее")
}

@Test func lastUserPromptNilWhenAbsent() {
    #expect(Transcript.lastUserPrompt(jsonl: "") == nil)
    #expect(Transcript.lastUserPrompt(jsonl: "not json") == nil)
}
