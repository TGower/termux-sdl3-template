# Native Android Game Development in Termux (SDL3)

This document outlines the proven, working procedure for setting up a purely native Android development environment (C/C++) directly inside Termux on a modern Android device (API 34+ / Android 14+), without needing a PC or Android Studio.

We specifically use **SDL3**, as it handles the modern Android lifecycle and OpenGL ES contexts far more robustly than other minimal frameworks (which often crash due to strict `NativeActivity` limitations on newer firmware).

## 1. The Core Problem: Why Standard Termux Tools Fail

You cannot use the standard `pkg install clang` compiler in Termux to build Android `.so` files for a standalone APK. 
*   **The Termux Compiler Trap:** Termux's compiler is heavily patched to build binaries *for Termux's custom environment*. It injects incorrect C-runtime initializers (`crtbegin_so.o`), links against Termux libraries instead of standard Android Bionic libraries, and uses an 8-byte TLS alignment.
*   **The Result:** If you package a `.so` built by Termux's `clang` into an APK, Android's `zygote` and `ActivityManager` will instantly abort the launch and crash the app because the library is structurally incompatible with a standard Android Dalvik/ART process.

## 2. Environment Setup

To solve this, we must download a **pristine, unpatched version of the official Google Android NDK** compiled to run natively on `aarch64` (ARM64).

### Step 1: Install Basic Tools
```bash
pkg update
pkg install -y wget p7zip unzip openjdk-17 cmake make aapt aapt2 dx apksigner
```

### Step 2: Download the Pristine AArch64 NDK
Google only provides x86_64 binaries. We use a community-compiled native version.
```bash
mkdir -p ~/android-ndk-aarch64
cd ~/android-ndk-aarch64
wget -qO ndk.7z "https://github.com/lzhiyong/termux-ndk/releases/download/android-ndk/android-ndk-r29-aarch64.7z"
7z x ndk.7z > /dev/null
mv android-ndk-r29/* .
rm -rf android-ndk-r29 ndk.7z
```

### Step 3: Setup the SDK Framework
You need `android.jar` to compile Java wrappers. (Assuming you have a standard Android SDK skeleton at `~/android-sdk/platforms/android-34/android.jar`).

### Step 4: Generate a Keystore
```bash
keytool -genkeypair -validity 10000 -dname "CN=Test,O=Android,C=US" -keystore ~/my.keystore -storepass 123456 -keypass 123456 -alias mykey -keyalg RSA -keysize 2048
```

---

## 3. Building SDL3

SDL3 must be built as a static library (`libSDL3.a`) using the pristine NDK and CMake.

```bash
git clone --depth 1 -b release-3.2.0 https://github.com/libsdl-org/SDL.git ~/SDL3
export NDK=~/android-ndk-aarch64
export TOOLCHAIN=$NDK/build/cmake/android.toolchain.cmake

mkdir -p ~/SDL3_build && cd ~/SDL3_build
cmake ~/SDL3 \
  -DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-34 \
  -DSDL_SHARED=OFF \
  -DSDL_STATIC=ON
make -j4
```
*Note: Some X11 warnings are normal; they are safely ignored.*

---

## 4. The Anatomy of a Modern Native Android App

Modern Android strictly forbids "pure" native apps (`android:hasCode="false"`) on many devices. The app *must* have a Dalvik executable (`classes.dex`). Therefore, we use a Java `Activity` to load our `.so` file via JNI.

### The C Code (`main_sdl.c`)
Standard SDL3 code using `SDL_main`.

```c
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

int main(int argc, char *argv[]) {
    SDL_Init(SDL_INIT_VIDEO);
    SDL_Window *window = SDL_CreateWindow("SDL3 Test", 800, 600, SDL_WINDOW_RESIZABLE);
    SDL_Renderer *renderer = SDL_CreateRenderer(window, NULL);
    
    int quit = 0;
    SDL_Event event;
    while (!quit) {
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) quit = 1;
        }
        SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255); // Green
        SDL_RenderClear(renderer);
        SDL_RenderPresent(renderer);
    }
    
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
```

### The Ultimate Build Script
This script compiles the C code, links the static C++ library (crucial to avoid `__gxx_personality_v0` crashes), compiles SDL's Java wrappers, and packages the APK.

**Crucial Linker Flag:** `-Wl,-z,max-page-size=16384` is required because modern devices (Pixel 8+, Android 15) enforce a 16KB memory page size. Without this, the library will crash instantly upon loading.

```bash
#!/bin/bash
set -e

# 1. Environment
export NDK=~/android-ndk-aarch64
export CC="$NDK/toolchains/llvm/prebuilt/linux-aarch64/bin/aarch64-linux-android34-clang"
export CXX="$NDK/toolchains/llvm/prebuilt/linux-aarch64/bin/aarch64-linux-android34-clang++"
export BUILD_DIR=~/build_sdl
export SDK_JAR=~/android-sdk/platforms/android-34/android.jar

rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR/{lib/arm64-v8a,bin,obj,res/values,src/org/libsdl/app,src/com/test/sdl}

# 2. Copy SDL Java Wrapper
cp ~/SDL3/android-project/app/src/main/java/org/libsdl/app/*.java $BUILD_DIR/src/org/libsdl/app/

# 3. Create Custom MainActivity
echo 'package com.test.sdl;
import org.libsdl.app.SDLActivity;
public class MainActivity extends SDLActivity {
    @Override protected String[] getLibraries() { return new String[] { "main" }; }
}' > $BUILD_DIR/src/com/test/sdl/MainActivity.java

# 4. Compile C Code
$CC -c main_sdl.c -o $BUILD_DIR/obj/main.o -I~/SDL3/include -fPIC -Wall

# 5. Link Shared Library (MAGIC SAUCE HERE)
# -CXX: Use clang++ for linking to resolve C++ exceptions inside SDL3
# -max-page-size=16384: Fixes instant crashes on modern 16KB page size devices
# -static-libstdc++: Bundles the C++ runtime directly into the library
$CXX -shared -o $BUILD_DIR/lib/arm64-v8a/libmain.so \
    $BUILD_DIR/obj/main.o ~/SDL3_build/libSDL3.a \
    -Wl,-z,max-page-size=16384 -Wl,-soname,libmain.so \
    -static-libstdc++ \
    -llog -landroid -lEGL -lGLESv1_CM -lGLESv2 -lOpenSLES -lm -lc

# 6. Compile Java and Dex
javac -source 1.8 -target 1.8 -bootclasspath $SDK_JAR -d $BUILD_DIR/obj $(find $BUILD_DIR/src -name "*.java")
dx --dex --output=$BUILD_DIR/bin/classes.dex $BUILD_DIR/obj

# 7. Manifest
echo '<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.test.sdl" android:versionCode="1" android:versionName="1.0">
    <uses-sdk android:minSdkVersion="29" android:targetSdkVersion="34" />
    <uses-feature android:glEsVersion="0x00020000" android:required="true" />
    <application android:hasCode="true" android:extractNativeLibs="true" android:label="SDL3 Test">
        <activity android:name="com.test.sdl.MainActivity" android:theme="@android:style/Theme.NoTitleBar.Fullscreen" android:configChanges="orientation|keyboardHidden|screenSize" android:screenOrientation="landscape" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>' > $BUILD_DIR/AndroidManifest.xml

# 8. Package (aapt2 is required for correct namespace linking)
aapt2 compile --dir $BUILD_DIR/res -o $BUILD_DIR/res.flata
aapt2 link -o $BUILD_DIR/bin/app.unsigned.apk --manifest $BUILD_DIR/AndroidManifest.xml -I $SDK_JAR $BUILD_DIR/res.flata
cd $BUILD_DIR
cp bin/classes.dex .
aapt add -0 .so bin/app.unsigned.apk classes.dex lib/arm64-v8a/libmain.so
cd ..

# 9. Align and Sign
zipalign -f -p 4 $BUILD_DIR/bin/app.unsigned.apk $BUILD_DIR/bin/app.aligned.apk
apksigner sign --ks ~/my.keystore --ks-pass pass:123456 --v2-signing-enabled true --v3-signing-enabled true --out $BUILD_DIR/bin/app.apk $BUILD_DIR/bin/app.aligned.apk

cp $BUILD_DIR/bin/app.apk /sdcard/Download/sdl_app.apk
echo "SUCCESS! Copied to /sdcard/Download/sdl_app.apk"
```
