#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

mkdir -p android/app/src/main/jniLibs

ANDROID_RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384"
if [ -n "${RUSTFLAGS:-}" ]; then
  RUSTFLAGS="$RUSTFLAGS $ANDROID_RUSTFLAGS"
else
  RUSTFLAGS=$ANDROID_RUSTFLAGS
fi
export RUSTFLAGS

if cargo ndk --version >/dev/null 2>&1; then
  cargo ndk \
    -t arm64-v8a \
    -t armeabi-v7a \
    -t x86_64 \
    -o android/app/src/main/jniLibs \
    build -p pawxy-jni --release
else
  printf '%s\n' "cargo-ndk is required to build Android JNI libraries." >&2
  printf '%s\n' "Install it with: cargo install cargo-ndk" >&2
  exit 1
fi

cd android
if [ -n "${GRADLE_BIN:-}" ]; then
  "$GRADLE_BIN" :app:assembleDebug
elif [ -x ./gradlew ]; then
  ./gradlew :app:assembleDebug
elif command -v gradle >/dev/null 2>&1; then
  gradle :app:assembleDebug
else
  printf '%s\n' "Gradle wrapper or gradle command not found." >&2
  exit 1
fi
