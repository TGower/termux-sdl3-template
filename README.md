# This was all vibe coded. Worked on my machine, able to create an android app completely standalone on my android tablet. YMMV. Slop below:
# Termux SDL3 Android Template

This repository provides a template for developing and building SDL3-based Android applications directly within Termux on an Android device.

## Prerequisites

- A modern Android device (Android 14+ recommended).
- [Termux](https://termux.dev/) installed.

## Getting Started

1.  **Clone this repository:**
    ```bash
    git clone <your-repo-url> termux-sdl3-template
    cd termux-sdl3-template
    ```

2.  **Run the setup script:**
    This script installs necessary packages, downloads a pristine AArch64 NDK, sets up a minimal Android SDK, clones SDL3, and builds the SDL3 static library.
    ```bash
    ./setup.sh
    ```

3.  **Build the APK:**
    This script compiles the C code, links it with SDL3, generates the Dalvik bytecode, and packages/signs the final APK.
    ```bash
    ./build.sh
    ```

## Project Structure

- `main_sdl.c`: Your application's entry point and main logic.
- `setup.sh`: Environment configuration script.
- `build.sh`: APK build and packaging script.
- `TERMUX_SDL3_ANDROID_SETUP.md`: Detailed documentation on the setup and its rationale.

## Installation

After a successful build, the APK will be located at `build_output/bin/app.apk`. If Termux has storage permissions, it will also be copied to your device's `Downloads` folder as `sdl_app.apk`.
