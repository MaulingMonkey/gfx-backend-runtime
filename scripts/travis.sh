#!/bin/bash

set -e
if [[ "$ANDROID_SDK_VERSION" == "" ]]; then export ANDROID_SDK_VERSION=21; fi
if [[ "$RUST_BACKTRACE"      == "" ]]; then export RUST_BACKTRACE=1;       fi # In case of panicing build scripts or tests


if [[ "$CLIPPY" != "" ]]; then
  rustup component add clippy
  cargo clippy
fi

if [[ "$TARGET" != "" ]]; then rustup target install $TARGET; fi

if [[ "$TARGET" == "wasm32-"* && "$TARGET" != "wasm32-wasi" ]]; then
  cargo-web --version || cargo install cargo-web
  cargo web build $FLAGS --target=$TARGET
  cargo web test  $FLAGS --target=$TARGET

elif [[ "$TARGET" == *"-linux-android"* ]]; then
  # Modern Java has trouble with sdkmanager: https://stackoverflow.com/questions/46402772/failed-to-install-android-sdk-java-lang-noclassdeffounderror-javax-xml-bind-a
  export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre/

  # Suppress warnings
  mkdir ~/.android
  touch ~/.android/repositories.cfg

  # See https://developer.android.com/studio#command-tools for latest version
  curl -L https://dl.google.com/android/repository/sdk-tools-linux-4333796.zip -o ~/android-sdk.zip
  unzip -q ~/android-sdk.zip -d ~/android-sdk
  export PATH="${HOME}/android-sdk/tools/bin:$PATH"                                             # sdkmanager etc.
  export PATH="${HOME}/android-sdk/ndk-bundle/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"  # Cross compilers
  yes | sdkmanager --licenses >/dev/null 2>/dev/null

  #sdkmanager --list
  sdkmanager "tools"                        | tr '\r' '\n' | grep -v %
  sdkmanager "platform-tools"               | tr '\r' '\n' | grep -v %
  sdkmanager "build-tools;27.0.3"           | tr '\r' '\n' | grep -v %
  sdkmanager "platforms;android-21"         | tr '\r' '\n' | grep -v %
  sdkmanager "ndk-bundle"                   | tr '\r' '\n' | grep -v %

  # cc crate isn't cool enough to use .cargo/config 's linker... although to be fair it's also trying to compile code...
  export COMPILER_PREFIX=$(echo $TARGET | sed s/armv7/armv7a/)
  export ETC_PREFIX=$(echo $TARGET | sed s/armv7/arm/)
  export AR=${ETC_PREFIX}-ar
  export AS=${ETC_PREFIX}-as
  export CC=${COMPILER_PREFIX}${ANDROID_SDK_VERSION}-clang
  export CXX=${COMPILER_PREFIX}${ANDROID_SDK_VERSION}-clang++
  export LD=${ETC_PREFIX}-ld

  pushd linux-android
    cargo build --target=$TARGET
    # Don't test, can't run android emulators successfully on travis currently
  popd

elif [[ "$TARGET" == *"-apple-ios" || "$TARGET" == "wasm32-wasi" ]]; then
  cargo build --target=$TARGET $FLAGS
  # Don't test
  #   iOS simulator setup/teardown is complicated
  #   cargo-web doesn't support wasm32-wasi yet, nor can wasm-pack test specify a target

elif [[ "$TARGET" == *"-unknown-linux-gnueabihf" ]]; then
  sudo apt-get update
  sudo apt-get install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
  pushd generic-cross
    cargo build --target=$TARGET $FLAGS
    # Don't test
  popd

elif [[ "$TARGET" != "" ]]; then
  pushd generic-cross
    cargo build --target=$TARGET $FLAGS
    cargo test  --target=$TARGET $FLAGS
  popd

else
  # Push nothing, target host CPU architecture
  cargo build $FLAGS
  cargo test  $FLAGS

fi
