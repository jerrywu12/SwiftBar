#!/bin/zsh

# SwiftBar indicator for active Codex task lifecycles plus standalone Claude
# Code and Gemini CLI workers. The first separator must remain on line 2 so
# SwiftBar never cycles dropdown details through the menu bar.
status_db=${CODEX_STATUS_DB:-/Users/jerry/.codex/state_5.sqlite}
bundled_rg=/Applications/ChatGPT.app/Contents/Resources/rg
[[ -x "$bundled_rg" ]] || bundled_rg=/opt/homebrew/bin/rg

typeset -a codex_tasks claude_tasks gemini_tasks antigravity_tasks
codex_count=0

if [[ -r "$status_db" && -x "$bundled_rg" ]]; then
  thread_rows=$(
    /usr/bin/sqlite3 -separator $'\t' "file:${status_db}?mode=ro" \
      "SELECT id,
              substr(replace(replace(replace(replace(title, char(9), ' '), char(10), ' '), char(13), ' '), '|', '¦'), 1, 60),
              source,
              replace(replace(replace(cwd, char(9), ' '), char(10), ' '), '|', '¦'),
              rollout_path
         FROM threads
        WHERE archived = 0
          AND updated_at >= strftime('%s','now') - 86400
        ORDER BY updated_at DESC;" 2>/dev/null
  )

  while IFS=$'\t' read -r thread_id thread_title thread_source thread_cwd rollout_path; do
    [[ -r "$rollout_path" ]] || continue

    lifecycle=$(
      /usr/bin/tail -c 262144 "$rollout_path" 2>/dev/null |
        "$bundled_rg" -o '"type":"task_(started|complete)"' 2>/dev/null |
        /usr/bin/tail -n 1
    )
    if [[ -z "$lifecycle" ]]; then
      lifecycle=$(
        "$bundled_rg" -o '"type":"task_(started|complete)"' "$rollout_path" 2>/dev/null |
          /usr/bin/tail -n 1
      )
    fi
    [[ "$lifecycle" == '"type":"task_started"' ]] || continue

    case "$thread_source" in
      exec) source_label='Automation/CLI' ;;
      vscode) source_label='Codex app' ;;
      *subagent*) source_label='Subagent' ;;
      *) source_label='Codex' ;;
    esac

    [[ -n "$thread_title" ]] || thread_title='Untitled task'
    workspace=${thread_cwd:t}
    [[ -n "$workspace" ]] || workspace='/.'
    codex_tasks+=("${source_label}"$'\t'"${thread_title}"$'\t'"${workspace}"$'\t'"${thread_id}")
    (( codex_count += 1 ))
  done <<< "$thread_rows"
fi

if [[ -n "${AGENT_STATUS_PS_FILE:-}" && -r "$AGENT_STATUS_PS_FILE" ]]; then
  process_rows=$(/bin/cat "$AGENT_STATUS_PS_FILE" 2>/dev/null)
else
  process_rows=$(/bin/ps -axo pid=,ppid=,etime=,command= 2>/dev/null)
fi

while IFS= read -r process_row; do
  [[ -n "$process_row" ]] || continue
  read -r pid ppid elapsed process_command <<< "$process_row"
  [[ -n "$pid" && -n "$elapsed" && -n "$process_command" ]] || continue

  if [[ "$process_command" =~ '^/.*\/claude([[:space:]]|$)' ]] &&
     [[ "$process_command" != /Applications/Claude.app/* ]]; then
    claude_tasks+=("${pid}"$'\t'"${elapsed}")
    continue
  fi

  if { [[ "$process_command" =~ '^/.*\/gemini([[:space:]]|$)' ]] ||
       [[ "$process_command" =~ '^([^ ]*/)?node[[:space:]].*@google/gemini-cli/.*\.js([[:space:]]|$)' ]]; } &&
     [[ "$process_command" != /Applications/Gemini.app/* ]]; then
    gemini_tasks+=("${pid}"$'\t'"${elapsed}")
  fi

  if { [[ "$process_command" =~ 'language_server_macos_arm' ]] && [[ "$process_command" != *'--enable_lsp'* ]]; } ||
     { [[ "$process_command" =~ '[aA]ntigravity' ]] &&
       [[ "$process_command" != *codex-status.5s.sh* ]] &&
       [[ "$process_command" != *"Google Chrome"* ]] &&
       [[ "$process_command" != */.antigravity-ide/extensions/* ]] &&
       [[ "$process_command" != /Applications/Antigravity\ IDE.app/* ]] &&
       [[ "$process_command" != /Applications/Antigravity.app/* ]]; }; then
    antigravity_tasks+=("${pid}"$'\t'"${elapsed}")
  fi
done <<< "$process_rows"

claude_count=${#claude_tasks[@]}
gemini_count=${#gemini_tasks[@]}
antigravity_count=${#antigravity_tasks[@]}

wrapped_matches=$(print -r -- "$process_rows" | /usr/bin/awk '/[c]affeinate -i \/opt\/homebrew\/bin\/codex/ { print $1, $3 }')
wrapped_count=$(print -r -- "$wrapped_matches" | /usr/bin/awk 'NF { total++ } END { print total + 0 }')

display_codex_count=$codex_count
(( display_codex_count == 0 && wrapped_count > 0 )) && display_codex_count=$wrapped_count
display_count=$(( display_codex_count + claude_count + gemini_count + antigravity_count ))

if (( display_count > 0 && wrapped_count > 0 )); then
  print "🤖 ${display_count} | color=#34C759"
elif (( display_count > 0 )); then
  print "🤖 ${display_count} | color=#FF9F0A"
else
  print "🤖 0 | color=#8E8E93"
fi

print -r -- "---"
if (( display_count > 0 )); then
  print "Active agent tasks: ${display_count} | color=#34C759"

  if (( display_codex_count > 0 )); then
    if (( codex_count > 0 )); then
      for task_record in "${codex_tasks[@]}"; do
        IFS=$'\t' read -r source_label thread_title workspace thread_id <<< "$task_record"
        print "Codex · ${source_label} · ${thread_title}"
        print -r -- "--${workspace} · ${thread_id[1,8]} | color=#8E8E93"
      done
    else
      print "Codex · ${display_codex_count} wrapped process(es)"
    fi
  fi

  for task_record in "${claude_tasks[@]}"; do
    IFS=$'\t' read -r pid elapsed <<< "$task_record"
    print "Claude · PID ${pid} · running ${elapsed}"
  done

  for task_record in "${gemini_tasks[@]}"; do
    IFS=$'\t' read -r pid elapsed <<< "$task_record"
    print "Gemini · PID ${pid} · running ${elapsed}"
  done

  for task_record in "${antigravity_tasks[@]}"; do
    IFS=$'\t' read -r pid elapsed <<< "$task_record"
    print "Antigravity · PID ${pid} · running ${elapsed}"
  done
else
  print "No active agent task | color=#8E8E93"
fi

print -r -- "---"
if (( wrapped_count > 0 )); then
  print "Codex-linked sleep prevention: active | color=#34C759"
  print -r -- "$wrapped_matches" | while read -r pid elapsed; do
    [[ -n "$pid" ]] && print "PID ${pid} · running ${elapsed}"
  done
else
  print "Codex-linked sleep prevention: inactive | color=#FF9F0A"
fi

print -r -- "---"
print "Open Activity Monitor | href=file:///System/Applications/Utilities/Activity%20Monitor.app"
print "Refresh | refresh=true"
