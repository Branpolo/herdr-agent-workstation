# SPEC I-2: an SSH-login tmux auto-start hook that stays out of herdr panes.
# herdr sets HERDR_ENV=1 in every pane; panes also inherit SSH_CONNECTION from the
# server's launch environment, so without the HERDR_ENV check every pane would
# `exec tmux attach`. Plain SSH logins behave as before. Bypass with NO_TMUX=1.
if [[ -z "$NO_TMUX" ]] && command -v tmux >/dev/null \
   && [[ -n "$SSH_CONNECTION" ]] \
   && [[ -z "$HERDR_ENV" ]] \
   && [[ -z "$TMUX" ]] \
   && [[ $- == *i* ]]; then
  if tmux has-session -t main 2>/dev/null; then
    exec tmux attach -t main
  else
    exec tmux new -s main
  fi
fi
