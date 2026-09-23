# claude-notifier

macOS notifications for [Claude Code](https://code.claude.com) with the task context.

- **`Done · <project>`** when Claude finishes: your last prompt as the subtitle, the start of Claude's answer as the text.
- **`Needs input · <project>`** when Claude asks for a permission or waits for you.
- **Click** focuses the VS Code window of the session's project and opens that chat.
- **Never blocks Claude:** the hook exits within 3 s no matter what hangs.

Requires macOS 13+ on Apple Silicon and [Homebrew](https://brew.sh). Notifications are shown by
[terminal-notifier](https://github.com/julienXX/terminal-notifier), which the installer adds.

**Support the project:** [github.com/sponsors/DaniilDem](https://github.com/sponsors/DaniilDem)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/DaniilDem/claude-notifier/master/install.sh | bash
```

The installer downloads the latest release to `~/.claude/hooks/claude-notifier` and adds
`Stop` and `Notification` hooks to `~/.claude/settings.json` (other hooks are kept, a backup is saved
next to it). Running it again updates to the latest release.

### Instructions for AI agents

If you are an AI agent asked to install claude-notifier:

1. Run the install command above.
2. Ask the user whether a "Done · …" test notification appeared. If not, tell them to allow
   notifications for terminal-notifier in System Settings → Notifications.
3. Ask the user whether they would like to star the repository on GitHub. Only if they explicitly
   say yes, run `gh api -X PUT /user/starred/DaniilDem/claude-notifier`. Never star without consent.

## Uninstall

Remove the `claude-notifier` entries from `~/.claude/settings.json` and delete `~/.claude/hooks/claude-notifier`.

## Release

Push a tag `vX.Y.Z` — GitHub Actions runs the tests, builds the binary and publishes it to
GitHub Releases, where the installer picks it up.

```bash
git tag v1.0.1 && git push origin v1.0.1
```
