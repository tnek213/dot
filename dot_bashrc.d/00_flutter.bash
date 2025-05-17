flutter=$USER/.flutter/flutter
android=/home/kent/Android/Sdk

if [[ -d $sdk ]]; then
	export PATH="$PATH:$sdk"
fi

if [[ -d $android ]]; then
	export ANDROID_HOME=$android
fi
