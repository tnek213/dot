# shellcheck disable=SC1091

if [ -f /usr/share/bash-completion/bash_completion ]; then
  source '/usr/share/bash-completion/bash_completion'
elif [ -f /etc/bash_completion ]; then
  source '/etc/bash_completion'
fi

shopt -s histappend
export HISTCONTROL='ignorespace:erasedups'
export HISTFILE=~/.bash_history
export HISTFILESIZE=100000
export HISTSIZE=1000
export HISTIGNORE='ls:cd:pwd:bg:fg:history'
# man 3 strftime
#   %d The day of the month as a decimal number (range 01 to 31)
#   %b The abbreviated month name according to the current locale
#   %a The abbreviated name of the day of the week according to the current locale
#   %M The minute as a decimal number (range 00 to 59).  (Calculated from tm_min.)
#   %R The  time in 24-hour notation (%H:%M).
export HISTTIMEFORMAT='%b %d - %a - %R     '

# Update the window size after each command if changed
shopt -s checkwinsize
