# Polar Saver

Open-source Android **Battery Manager, Duplicate File Finder, and Device Health Utility** styled in **Royal Blue, Powder Blue, Silver, and White** with a custom **Polar Bear Battery Shield** logo.

## Features
- **Live Battery Dashboard:** Real-time charge ring gauge, charging status, Power Saver detection, and estimated runtime/charge time.
- **Battery Lifespan Charge Alert:** Customizable charge-limit reminder (default 80%) to reduce lithium-ion battery wear.
- **SHA-256 Duplicate File Scanner (`lib/storage_scanner.dart`):** Groups files by size and verifies exact matches with cryptographic SHA-256 hashing so you can safely delete extra copies.
- **Residual Temp & Empty Folder Cleaner:** Scans for `.tmp`, `.log`, `.bak`, `.cache` files and orphaned empty folders. *(Note: Android does not have a Windows-style registry—cleaning residual temp files and empty folders is the real Android equivalent.)*

## Build Your APK in the Cloud (No Local Setup Required)
1. Create a free repository on GitHub (e.g., `polar-saver`).
2. Extract this ZIP and upload all files (including `.github/workflows/build_apk.yml`) to the `main` branch.
3. Open the **Actions** tab -> **Build Polar Saver APK**.
4. Download **`PolarSaver-APK`** from the **Artifacts** section, unzip it, and install `PolarSaver-release.apk` on your Android phone.
