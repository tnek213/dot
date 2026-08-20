if command -v go 2>/dev/null; then
  export PATH="$(go env GOPATH 2>/dev/null || echo $HOME/go)/bin:$PATH"
fi
