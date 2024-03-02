# shellcheck disable=SC1091

___JAVA_HOME=$(
  find "$HOME/.local/share/" -maxdepth 1 -type d -name 'jdk-*' \
    -exec test -x '{}/bin/javac' \; -print |
    sort -Vr | sed -n '1p'
)

if [ -n "$___JAVA_HOME" ]; then
  export JAVA_HOME="$___JAVA_HOME"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
