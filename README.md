# claude-notifier

macOS notifications for [Claude Code](https://code.claude.com) with the task context.
Fork of [alerter](https://github.com/vjeantet/alerter) (its original README is below).

- **`Готово · <project>`** ("Done") when Claude finishes: your last prompt as the subtitle, the start of Claude's answer as the text.
- **`Нужен ответ · <project>`** ("Needs input") when Claude asks for a permission or waits for you.
- **Click** focuses the VS Code window of the session's project and opens that chat.
- **Never blocks Claude:** the hook exits within 3 s no matter what hangs.

Notifications are shown by [terminal-notifier](https://github.com/julienXX/terminal-notifier).
Allow/Deny and AskUserQuestion answer buttons are implemented (`PermissionRequest`,
`PreToolUse` + `AskUserQuestion` hooks) but not recommended on macOS 15 — see
[the design notes](docs/superpowers/specs/2026-09-23-claude-notifier-design.md).

**Support the project:** [github.com/sponsors/DaniilDem](https://github.com/sponsors/DaniilDem)

## Installation (instructions for AI agents)

If you are an AI coding agent asked to install claude-notifier, follow these steps in order.
Ask the user before doing anything not listed here.

**1. Check prerequisites.** Stop and tell the user if any is missing:

- macOS 13+ on Apple Silicon (Homebrew in `/opt/homebrew` — the terminal-notifier path is hardcoded).
- Swift toolchain: `swift --version` (Xcode or Command Line Tools).
- Homebrew: `brew --version`.
- Click-to-open-chat works only with the Claude Code extension for VS Code.

**2. Install terminal-notifier** (skip if `/opt/homebrew/bin/terminal-notifier` exists):

```bash
brew install terminal-notifier
```

**3. Build and install the binary:**

```bash
git clone https://github.com/DaniilDem/claude-notifier.git ~/claude-notifier
cd ~/claude-notifier && swift build -c release
mkdir -p ~/.claude/hooks && cp .build/release/alerter ~/.claude/hooks/claude-notifier
```

**4. Register the hooks.** `~/.claude/settings.json` usually already has other hooks — append,
never replace them. Back up first. This script is idempotent:

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak-claude-notifier 2>/dev/null || echo '{}' > ~/.claude/settings.json
python3 - <<'EOF'
import json, pathlib
p = pathlib.Path.home() / ".claude/settings.json"
d = json.loads(p.read_text())
hooks = d.setdefault("hooks", {})
cmd = '"$HOME/.claude/hooks/claude-notifier" hook'
ours = {"type": "command", "command": cmd, "timeout": 5}
for event in ["Stop", "Notification"]:
    hooks[event] = [g for g in hooks.get(event, [])
                    if not any("claude-notifier" in h.get("command", "") for h in g.get("hooks", []))]
hooks["Stop"].append({"hooks": [ours]})
hooks["Notification"].append({"matcher": "permission_prompt|idle_prompt|elicitation_dialog", "hooks": [ours]})
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
EOF
python3 -c "import json, os; json.load(open(os.path.expanduser('~/.claude/settings.json')))" && echo "settings.json is valid"
```

**5. Verify.** It must exit within 3 s with exit code 0:

```bash
echo '{"hook_event_name":"Stop","session_id":"test","cwd":"'"$PWD"'","last_assistant_message":"claude-notifier works"}' \
  | ~/.claude/hooks/claude-notifier hook; echo "exit=$?"
```

Ask the user whether a "Готово · …" notification appeared (notification texts are in Russian). If not: System Settings → Notifications →
terminal-notifier → Allow notifications. If hooks don't fire in the current session, restart Claude Code.

**6. Offer a star.** Ask the user whether they would like to star the repository on GitHub.
Only if they explicitly say yes, run:

```bash
gh api -X PUT /user/starred/DaniilDem/claude-notifier
```

Never star without the user's explicit consent.

**Uninstall:** remove the `claude-notifier` entries from `~/.claude/settings.json` and delete
`~/.claude/hooks/claude-notifier`.

---

# Alerter

Alerter is a command-line tool for sending macOS notifications (alerts), built with Swift and Swift Package Manager.
The program exits when the user interacts with the alert or when it is dismissed, printing the result to stdout as plain text or JSON.

Alerts are macOS notifications that stay on screen until dismissed. Requires macOS 13.0 or later.

Two kinds of alerts can be triggered: **Reply Alert** and **Actions Alert**.

> [!IMPORTANT]
> **Version 26.xxx** — Alerter has been completely rewritten in Swift with the Swift Package Manager. \
> The CLI syntax now uses double dashes (--message, --title, --json...) and installation is done via Homebrew: `brew install vjeantet/tap/alerter`. \
> See the [release notes](docs/release-notes-26.2.md) for all the details.


## Reply alert
Displays a notification with a "Reply" button that opens a text input field.

## Actions alert
Displays a notification with one or more action buttons to click on.

## Features
* Set the alert icon, title, subtitle, and image.
* Capture text typed by the user in reply-type alerts.
* Delay: defer notification delivery by a given number of seconds.
* Schedule: deliver a notification at a specific time (HH:mm or yyyy-MM-dd HH:mm).
* Timeout: automatically close the alert after a delay.
* Customize the close button label.
* Customize the actions dropdown label.
* Play a sound when delivering the notification.
* Plain text or JSON output for alert events (closed, timeout, replied, activated, etc.).
* Ignore Do Not Disturb mode.
* Gracefully close the notification on SIGINT and SIGTERM.

## Installation

### Homebrew (recommended)

```bash
brew install vjeantet/tap/alerter
```

### MacPorts

```bash
sudo port install alerter
```

### Manual

1. Download the zipped precompiled binary from the
[releases section](https://github.com/vjeantet/alerter/releases).
2. Extract the binary.
3. Place it in a directory listed in your `$PATH` (e.g. `/usr/local/bin`).

### Build from source

```bash
git clone https://github.com/vjeantet/alerter.git
cd alerter
swift build -c release
# Binary is at .build/release/alerter
```

## Release workflow

Versioning uses the format `YY.N` (e.g. `26.1`, `26.2`). The version is bumped automatically.

```
1. ./scripts/release.sh                    # bump version, build, sign, notarize, tag, GitHub Release
2. ./scripts/update-homebrew-formula.sh     # update formula in vjeantet/homebrew-tap
3. ./scripts/update-macports-portfile.sh    # update local macports/Portfile, then submit PR to macports-ports
```

## Usage

```
$ ./alerter --message|--group|--list [VALUE|ID|ID] [options]
```

Examples:

Display piped data with a sound

```
$ echo 'Piped Message Data!' | alerter --sound default
```

![Display piped data with a sound](/img1.png?raw=true "")

Multiple actions and custom dropdown list
```
./alerter --message "Deploy now on UAT ?" --actions "Now,Later today,Tomorrow" --dropdown-label "When ?"
```

![Multiple actions and custom dropdown list](/img2.png?raw=true "")

Yes or No?
```
./alerter --title ProjectX --subtitle "new tag detected" --message "Deploy now on UAT ?" --close-label No --actions Yes --app-icon http://vjeantet.fr/images/logo.png
```

![Yes or No](/img3.png?raw=true "")

What is the name of this release?
```
./alerter --reply "Type release name" --message "What is the name of this release?" --title "Deploy in progress..."
```

![What is the name of this release](/img4.png?raw=true "")

## Options

At a minimum, you must specify either `--message`, `--remove`, or `--list`.

-------------------------------------------------------------------------------

`--message VALUE`  **[required]**

The message body of the notification.

Note that if this option is omitted and data is piped to the application, that
data will be used instead.

-------------------------------------------------------------------------------

`--reply TEXT`

Displays the notification as a reply-type alert. TEXT is used as placeholder text in the input field.

-------------------------------------------------------------------------------

`--actions VALUE1,VALUE2,"VALUE 3"`

The available notification actions.
When more than one value is provided, a dropdown is displayed.
You can customize the dropdown label with the `--dropdown-label` option.
Cannot be combined with `--reply`.

-------------------------------------------------------------------------------

`--dropdown-label VALUE`

The label for the actions dropdown (only used when multiple `--actions` values are provided).
Cannot be combined with `--reply`.

-------------------------------------------------------------------------------

`--close-label VALUE`

A custom label for the notification's "Close" button.

-------------------------------------------------------------------------------

`--title VALUE`

The title of the notification. Defaults to 'Terminal'.

-------------------------------------------------------------------------------

`--subtitle VALUE`

The subtitle of the notification.

-------------------------------------------------------------------------------

`--delay NUMBER`

Wait NUMBER seconds before delivering the notification. Defaults to 0 (immediate delivery).
If a signal (SIGINT/SIGTERM) is received during the delay, the process exits silently without delivering.
When combined with `--timeout`, the timeout starts after the notification is delivered.
Cannot be combined with `--at`.

-------------------------------------------------------------------------------

`--at TIME`

Deliver the notification at a specific time. Accepts two formats:
- `HH:mm` — next occurrence of that time (e.g. `14:30`). If the time matches the current minute, delivers immediately; if it has already passed today, schedules for tomorrow.
- `yyyy-MM-dd HH:mm` — a specific date and time (e.g. `2026-03-15 09:00`). Must be in the future.

Times are interpreted in the system's local timezone.
If a signal (SIGINT/SIGTERM) is received while waiting, the process exits silently without delivering.
When combined with `--timeout`, the timeout starts after the notification is delivered.
Cannot be combined with `--delay`.

-------------------------------------------------------------------------------

`--timeout NUMBER`

Automatically close the notification after NUMBER seconds. Defaults to 0 (no timeout).

-------------------------------------------------------------------------------

`--sound NAME`

The name of a sound to play when the notification appears. The names are listed
in Sound Preferences. Use 'default' for the default notification sound.

-------------------------------------------------------------------------------

`--json`

Output the result as a JSON object describing the alert event.

-------------------------------------------------------------------------------

`--group ID`

Specifies the 'group' a notification belongs to. For any 'group' only _one_
notification will ever be shown, replacing previously posted notifications.

A notification can be explicitly removed with the `--remove` option, described
below.

Examples:

* The sender's name, to scope notifications by tool.
* The sender's process ID, to scope notifications by process.
* The current working directory, to scope notifications by project.

-------------------------------------------------------------------------------

`--remove ID`  **[required]**

Removes a previously sent notification with the specified 'group' ID,
if one exists. Use the special group "ALL" to remove all notifications.

-------------------------------------------------------------------------------

`--list ID` **[required]**

Lists details about the specified 'group' ID. Use the special group
"ALL" to list all currently active notifications.

Output is a JSON array of notifications.

-------------------------------------------------------------------------------

`--sender ID`

Makes the notification appear as if it was sent by the specified application,
including using its icon. Defaults to `com.apple.Terminal`.

When this option is used, clicking the notification will launch the impersonated
application instead of alerter.

-------------------------------------------------------------------------------

`--app-icon PATH`

The path or URL of an image to display instead of the application icon.

**WARNING: This option relies on a private API and may break in future macOS releases.**

-------------------------------------------------------------------------------

`--content-image PATH`

The path or URL of an image to display inside the notification.

**WARNING: This option relies on a private API and may break in future macOS releases.**

-------------------------------------------------------------------------------

`--ignore-dnd`

Sends the notification even if Do Not Disturb is enabled.

**WARNING: This option relies on a private API and may break in future macOS releases.**

-------------------------------------------------------------------------------


## Shell script example
```bash
ANSWER="$(./alerter --message 'Start now ?' --close-label No --actions 'YES,MAYBE,one more action' --timeout 10)"
case $ANSWER in
    "@TIMEOUT") echo "Timeout man, sorry" ;;
    "@CLOSED") echo "You clicked on the default alert' close button" ;;
    "@CONTENTCLICKED") echo "You clicked the alert's content !" ;;
    "@ACTIONCLICKED") echo "You clicked the alert default action button" ;;
    "MAYBE") echo "Action MAYBE" ;;
    "NO") echo "Action NO" ;;
    "YES") echo "Action YES" ;;
    **) echo "? --> $ANSWER" ;;
esac
```

## Support & Contributors

### Code Contributors

This project exists thanks to all the people who contribute. [[Contribute](CONTRIBUTING.md)].

This project is based on a fork of [terminal notifier](https://github.com/julienXX/terminal-notifier) by [@JulienXX](https://github.com/julienXX).

## License

All work is available under the MIT license.

Copyright (C) 2012-2026 Valère Jeantet <valere.jeantet@gmail.com>, Eloy Durán <eloy.de.enige@gmail.com>, Julien Blanchard
<julien@sideburns.eu>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
