#!/bin/bash
set -e

# 1. Environment (Expects these in home as per setup.sh)
export NDK=~/android-ndk-aarch64
export SDL3_DIR=~/SDL3
export SDL3_BUILD_DIR=~/SDL3_build
export SDK_JAR=~/android-sdk/platforms/android-34/android.jar
export KEYSTORE=~/my.keystore

# Tools from NDK
export CC="$NDK/toolchains/llvm/prebuilt/linux-aarch64/bin/aarch64-linux-android34-clang"
export CXX="$NDK/toolchains/llvm/prebuilt/linux-aarch64/bin/aarch64-linux-android34-clang++"

# Project Specifics
export PROJECT_DIR=$(pwd)
export BUILD_DIR=$PROJECT_DIR/build_output

# Clean and recreate build directory
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR/{lib/arm64-v8a,bin,obj,res/values,src/org/libsdl/app,src/com/test/sdl}

echo "Building SDL3 Android App..."

# 2. Copy SDL Java Wrapper
cp $SDL3_DIR/android-project/app/src/main/java/org/libsdl/app/*.java $BUILD_DIR/src/org/libsdl/app/

# 3. Create Custom MainActivity
echo 'package com.test.sdl;
import org.libsdl.app.SDLActivity;
public class MainActivity extends SDLActivity {
    @Override protected String[] getLibraries() { return new String[] { "main" }; }
}' > $BUILD_DIR/src/com/test/sdl/MainActivity.java

# 4. Compile C Code
echo "Compiling C code..."
$CC -c $PROJECT_DIR/main_sdl.c -o $BUILD_DIR/obj/main.o -I$SDL3_DIR/include -fPIC -Wall

# 5. Link Shared Library
echo "Linking shared library..."
$CXX -shared -o $BUILD_DIR/lib/arm64-v8a/libmain.so \
    $BUILD_DIR/obj/main.o $SDL3_BUILD_DIR/libSDL3.a \
    -Wl,-z,max-page-size=16384 -Wl,-soname,libmain.so \
    -static-libstdc++ \
    -llog -landroid -lEGL -lGLESv1_CM -lGLESv2 -lOpenSLES -lm -lc

# 6. Compile Java and Dex
echo "Compiling Java and Dex..."
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

# 8. Package
echo "Packaging APK..."
aapt2 compile --dir $BUILD_DIR/res -o $BUILD_DIR/res.flata
aapt2 link -o $BUILD_DIR/bin/app.unsigned.apk --manifest $BUILD_DIR/AndroidManifest.xml -I $SDK_JAR $BUILD_DIR/res.flata
cd $BUILD_DIR
cp bin/classes.dex .
aapt add -0 .so bin/app.unsigned.apk classes.dex lib/arm64-v8a/libmain.so
cd ..

# 9. Align and Sign
echo "Aligning and Signing..."
zipalign -f -p 4 $BUILD_DIR/bin/app.unsigned.apk $BUILD_DIR/bin/app.aligned.apk
apksigner sign --ks $KEYSTORE --ks-pass pass:123456 --v2-signing-enabled true --v3-signing-enabled true --out $BUILD_DIR/bin/app.apk $BUILD_DIR/bin/app.aligned.apk

# 10. Final APK location
echo "-------------------------------------------------------"
echo "BUILD COMPLETE!"
echo "APK is at: $BUILD_DIR/bin/app.apk"
echo "-------------------------------------------------------"

# Optional: copy to /sdcard/Download if possible
if [ -d /sdcard/Download ]; then
    cp $BUILD_DIR/bin/app.apk /sdcard/Download/sdl_app.apk
    echo "Copied to /sdcard/Download/sdl_app.apk"
fi
