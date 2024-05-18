# shellcheck disable=SC1091

if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    __BASHRC_PHASE_PARALLEL_SOURCE_ADD '/usr/share/bash-completion/bash_completion'
  elif [ -f /etc/bash_completion ]; then
    __BASHRC_PHASE_PARALLEL_SOURCE_ADD '/etc/bash_completion'
  fi
fi
