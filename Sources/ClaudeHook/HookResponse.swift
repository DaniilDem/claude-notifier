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
