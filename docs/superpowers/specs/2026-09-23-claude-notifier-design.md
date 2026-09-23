# claude-notifier: уведомления macOS для Claude Code

Форк [vjeantet/alerter](https://github.com/vjeantet/alerter). Добавляет подкоманду `hook`,
которая подключается к хукам Claude Code и показывает уведомления с контекстом задачи,
кнопками ответа и переходом в нужный чат VS Code.

## Цели

1. В уведомлении виден контекст: проект, запрос пользователя, начало ответа Claude, команда/файл.
2. Клик по уведомлению открывает VS Code на чате этой сессии.
3. Запрос разрешения — кнопки Allow / Deny. Вопрос Claude (AskUserQuestion) — кнопки с вариантами.

Не цели: уведомления на телефон, поддержка терминалов кроме VS Code, UNUserNotificationCenter.

## Интерфейс

```
claude-notifier hook            # читает JSON хука Claude Code из stdin
```

Остальные опции alerter не меняются. Бинарник: `~/.claude/hooks/claude-notifier`.

`~/.claude/settings.json`:

| Событие | matcher | timeout хука |
|---|---|---|
| `Stop` | — | 10 |
| `Notification` | `idle_prompt\|elicitation_dialog` | 10 |
| `PermissionRequest` | — | 60 |
| `PreToolUse` | `AskUserQuestion` | 60 |

`Notification` с `permission_prompt` не подключаем: это событие закрывает `PermissionRequest`.

## Что показываем

Отправитель — `com.microsoft.VSCode` (механизм `--sender` alerter). Claude.app не подходит: с его bundle id делегат NSUserNotificationCenter не получает ни доставку, ни клики.

| Событие | title | subtitle | message | кнопки | звук |
|---|---|---|---|---|---|
| Stop | `Готово · <проект>` | первая строка последнего запроса пользователя | `last_assistant_message`, до 200 символов | нет | Glass |
| Notification | `Нужен ответ · <проект>` | — | `message` из хука | нет | Ping |
| PermissionRequest | `Разрешить? · <проект>` | `tool_name` | `tool_input.command` / `file_path` / `url`, иначе JSON `tool_input`, до 200 символов | Allow (action), Deny (close) | Ping |
| AskUserQuestion | `Вопрос · <проект>` | `header` вопроса | `question` | варианты `label` (1 шт. — кнопка, больше — выпадающий список «Ответить»), close «Позже» | Ping |

Ограничение alerter: нажатие close-кнопки и смахивание уведомления неотличимы (оба — `closed` со
значением close-кнопки). Поэтому смахнутый запрос разрешения = Deny (безопасная сторона),
смахнутый вопрос = «Позже» (решения нет).

`<проект>` — `basename(cwd)`. Последний запрос пользователя берём из `transcript_path`
(последняя запись `type: "user"` с текстовым содержимым, не tool_result). Не нашли — subtitle пустой.

## Клик по телу уведомления

`open "vscode://anthropic.claude-code/open?session=<session_id>"` — обработчик `/open` в расширении
Claude Code (проверено в `extension.js` v2.1.280). Открывает чат в последнем активном окне VS Code.

## Блокирующие события (PermissionRequest, AskUserQuestion)

1. Если активное приложение — VS Code (`NSWorkspace.frontmostApplication.bundleIdentifier ==
   "com.microsoft.VSCode"`), уведомление не показываем, выходим без вывода.
2. Иначе показываем уведомление с `timeout = 45` и ждём результата в том же процессе.
3. Результат → stdout:
   - Allow → решение «allow» в формате `PermissionRequest`.
   - Deny → решение «deny».
   - вариант вопроса → `PreToolUse` с `permissionDecision: "allow"` и `updatedInput` =
     исходный `tool_input` + `answers: { "<question>": "<label>" }`.
   - клик по телу → открыть чат, вывода нет.
   - «Позже» / таймаут → вывода нет.
   «Нет вывода» = Claude показывает обычное окно в VS Code. Молча ничего не разрешается.

Точный формат вывода обоих хуков и то, что Claude принимает `answers` из `updatedInput`,
проверяются экспериментом до реализации. Если `answers` не принимаются — варианты не
показываем, уведомление вопроса ведёт себя как Notification (клик открывает чат).

Обрабатываем только вопрос с одним элементом `questions` и `multiSelect: false`.
Иначе — уведомление как Notification.

## Неблокирующие события (Stop, Notification)

Хук читает stdin, запускает свою копию в фоне (`Process`, отвязанный от родителя,
payload передаётся через временный файл) и сразу выходит с кодом 0. Фоновая копия показывает
уведомление с `timeout = 1800` и по клику открывает чат. `group` = `claude-<session_id>`,
чтобы новое уведомление той же сессии заменяло старое.

## Ошибки

Любая ошибка (невалидный JSON, нет поля, не удалось доставить) → выход 0 без stdout.
Хук никогда не ломает работу Claude.

## Проверка

- `echo '<json>' | .build/debug/alerter hook` для каждого события — сверить stdout и уведомление.
  Примеры JSON — в `docs/claude-hook-samples/`.
- Живой прогон в VS Code: запрос разрешения на Bash, AskUserQuestion, завершение задачи, клик по уведомлению.
- Автотестов нет (как и в исходном alerter).

## Установка

`swift build -c release` → копия бинарника в `~/.claude/hooks/claude-notifier`,
обновить хуки в `~/.claude/settings.json`, удалить `~/.claude/hooks/claude-notify.sh`.
