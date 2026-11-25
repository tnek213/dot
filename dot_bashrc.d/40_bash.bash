# shellcheck disable=SC1091

if [ -f /usr/share/bash-completion/bash_completion ]; then
  source '/usr/share/bash-completion/bash_completion'
elif [ -f /etc/bash_completion ]; then
  source '/etc/bash_completion'
fi

# Place bash history under XDG_STATE_HOME instead of $HOME.
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/bash"
export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"

shopt -s histappend
export HISTCONTROL='ignorespace'
export HISTFILESIZE=100000
export HISTSIZE=100000
export HISTIGNORE='ls:cd:pwd:bg:fg:history'
# Flush each command to $HISTFILE immediately so killed/crashed shells
# don't lose history. Prepend so later PROMPT_COMMAND hooks (e.g. starship) chain after.
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
# man 3 strftime
#   %d The day of the month as a decimal number (range 01 to 31)
#   %b The abbreviated month name according to the current locale
#   %a The abbreviated name of the day of the week according to the current locale
#   %M The minute as a decimal number (range 00 to 59).  (Calculated from tm_min.)
#   %R The  time in 24-hour notation (%H:%M).
export HISTTIMEFORMAT='%b %d - %a - %R     '

# Update the window size after each command if changed
shopt -s checkwinsize
