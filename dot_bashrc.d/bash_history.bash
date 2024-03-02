shopt -s histappend
HISTCONTROL='ignorespace:erasedups'
HISTFILE=~/.bash_history
HISTFILESIZE=100000
HISTSIZE=1000
HISTIGNORE='ls:cd:pwd:bg:fg:history'

# man 3 strftime
#   %d The day of the month as a decimal number (range 01 to 31)
#   %b The abbreviated month name according to the current locale
#   %a The abbreviated name of the day of the week according to the current locale
#   %M The minute as a decimal number (range 00 to 59).  (Calculated from tm_min.)
#   %R The  time in 24-hour notation (%H:%M).
HISTTIMEFORMAT='%b %d - %a - %R     '
