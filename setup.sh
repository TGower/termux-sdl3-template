#!/bin/bash
set -e

echo "Setting up SDL3 Android Development Environment in Termux..."

# 1. Update and Install Basic Tools
echo "Installing dependencies..."
pkg update
pkg install -y wget p7zip unzip openjdk-17 cmake make aapt aapt2 dx apksigner git

# 2. Setup SDK/NDK Directories
mkdir -p ~/android-ndk-aarch64
mkdir -p ~/android-sdk/platforms/android-34

# 3. Download the Pristine AArch64 NDK (if not already present)
if [ ! -f ~/android-ndk-aarch64/source.properties ]; then
    echo "Downloading and extracting AArch64 NDK..."
    cd ~/android-ndk-aarch64
    wget -qO ndk.7z "https://github.com/lzhiyong/termux-ndk/releases/download/android-ndk/android-ndk-r29-aarch64.7z"
    7z x ndk.7z > /dev/null
    mv android-ndk-r29/* . 2>/dev/null || true
    rm -rf android-ndk-r29 ndk.7z
    cd -
else
    echo "NDK already present."
fi

# 4. Setup the SDK Framework (android.jar)
# We need an android.jar. If it doesn't exist, we try to download a minimal one or 
# assume the user will provide it. For a truly "fresh" install, we should fetch it.
if [ ! -f ~/android-sdk/platforms/android-34/android.jar ]; then
    echo "Downloading official Android 34 SDK (android.jar)..."
    wget -qO ~/platform-34.zip "https://dl.google.com/android/repository/platform-34-ext12_r01.zip"
    unzip -p ~/platform-34.zip android-34-ext12/android.jar > ~/android-sdk/platforms/android-34/android.jar
    rm ~/platform-34.zip
fi

# 5. Generate a Keystore (if not present)
if [ ! -f ~/my.keystore ]; then
    echo "Generating debug keystore..."
    keytool -genkeypair -validity 10000 -dname "CN=Test,O=Android,C=US" -keystore ~/my.keystore -storepass 123456 -keypass 123456 -alias mykey -keyalg RSA -keysize 2048
else
    echo "Keystore already present."
fi

# 6. Clone and Build SDL3
if [ ! -d ~/SDL3 ]; then
    echo "Cloning SDL3..."
    git clone --depth 1 -b release-3.2.0 https://github.com/libsdl-org/SDL.git ~/SDL3
fi

if [ ! -f ~/SDL3_build/libSDL3.a ]; then
    echo "Building SDL3 static library..."
    export NDK=~/android-ndk-aarch64
    export TOOLCHAIN=$NDK/build/cmake/android.toolchain.cmake

    mkdir -p ~/SDL3_build && cd ~/SDL3_build
    cmake ~/SDL3 \
      -DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN \
      -DANDROID_ABI=arm64-v8a \
      -DANDROID_PLATFORM=android-34 \
      -DSDL_SHARED=OFF \
      -DSDL_STATIC=ON
    make -j$(nproc)
    cd -
else
    echo "SDL3 already built."
fi

echo "-------------------------------------------------------"
echo "SETUP COMPLETE!"
echo "You can now run ./build.sh to create your APK."
echo "-------------------------------------------------------"
