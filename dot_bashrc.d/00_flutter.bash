sdk=$USER/.flutter/flutter

if [[ -d $sdk ]]; then
	PATH="$PATH:$sdk"
fi
