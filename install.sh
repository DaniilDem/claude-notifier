#!/bin/bash
# claude-notifier installer:
#   curl -fsSL https://raw.githubusercontent.com/DaniilDem/claude-notifier/master/install.sh | bash
set -euo pipefail

REPO="DaniilDem/claude-notifier"
BIN="$HOME/.claude/hooks/claude-notifier"
SETTINGS="$HOME/.claude/settings.json"

fail() { echo "claude-notifier: $*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || fail "needs macOS on Apple Silicon"

if [ ! -x /opt/homebrew/bin/terminal-notifier ]; then
  command -v brew >/dev/null || fail "Homebrew is required: https://brew.sh"
  brew install terminal-notifier
fi

echo "Downloading the latest release..."
mkdir -p "$(dirname "$BIN")"
curl -fsSL "https://github.com/$REPO/releases/latest/download/claude-notifier" -o "$BIN.tmp"
chmod +x "$BIN.tmp"
mv "$BIN.tmp" "$BIN"

# Register Stop + Notification hooks: keep all other hooks, replace old claude-notifier entries.
# JavaScript for Automation ships with macOS (python3 may be missing) and keeps key order.
backup=""
if [ -f "$SETTINGS" ]; then
  backup="$SETTINGS.bak-claude-notifier"
  cp "$SETTINGS" "$backup"
fi
js=$(mktemp -t claude-notifier)
trap 'rm -f "$js"' EXIT
cat > "$js" <<'EOF'
ObjC.import('Foundation');
function run(argv) {
  const [path, command] = argv;
  const fm = $.NSFileManager.defaultManager;
  const text = fm.fileExistsAtPath(path)
    ? ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null))
    : '';
  const settings = JSON.parse(text && text.trim() ? text : '{}');
  const hooks = settings.hooks = settings.hooks || {};
  const ours = { type: 'command', command: command, timeout: 5 };
  for (const event of ['Stop', 'Notification']) {
    hooks[event] = (hooks[event] || []).filter(
      group => !(group.hooks || []).some(hook => String(hook.command || '').includes('claude-notifier')));
  }
  hooks.Stop.push({ hooks: [ours] });
  hooks.Notification.push({ matcher: 'permission_prompt|idle_prompt|elicitation_dialog', hooks: [ours] });
  fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(
    $(path).stringByDeletingLastPathComponent, true, $(), null);
  const ok = $(JSON.stringify(settings, null, 2) + '\n')
    .writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
  if (!ok) throw new Error('cannot write ' + path);
}
EOF
osascript -l JavaScript "$js" "$SETTINGS" '"$HOME/.claude/hooks/claude-notifier" hook' >/dev/null

printf '{"hook_event_name":"Stop","session_id":"install-check","cwd":"%s","last_assistant_message":"claude-notifier is installed"}' "$PWD" \
  | "$BIN" hook

echo "claude-notifier installed: $BIN"
echo "A test notification should appear now. If it doesn't: System Settings → Notifications → terminal-notifier → Allow."
echo "Hooks registered in $SETTINGS${backup:+ (backup: $backup)}."
