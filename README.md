# DreamStream 📹✨

**DreamStream** is a lightning-fast, localized video broadcasting app that seamlessly turns your Android smartphone into a high-quality wireless (or wired) webcam for your PC. By streaming MJPEG directly to OBS Studio, DreamStream handles video with extremely low latency and high stability. 

> *Note: This project was **vibecoded** to life!* ✨

## 🌟 Features
- **Zero-Friction QR Pairing**: Simply click the QR code button on the PC app and scan it with your Android device to automatically handshake and pair over your local Wi-Fi. 
- **MJPEG Broadcast**: Broadcast raw MJPEG frames securely to a local HTTP server on your PC, ready to be instantly ingested by OBS Studio (`http://127.0.0.1:8081`).
- **Performance Optimized**: Includes features like a "Hide Preview" button on the Windows app to ensure you aren't wasting desktop GPU/CPU resources on rendering frames when you only need to route them to OBS.
- **Dynamic Localization**: Built with a custom, lightweight JSON localization engine (`assets/lang/en.json`), making it trivial to instantly translate the UI into any language. 

## 📋 Requirements
To build and run DreamStream, you will need the following dependencies installed on your system:
- **Flutter SDK**: `^3.12.0` (or the latest stable channel)
- **Android SDK**: For compiling and deploying the Android application.
- **Windows Development SDK (Visual Studio)**: Required for compiling the Windows desktop receiver application.
- **Hardware Requirements**: 
  - An Android device with a working camera.
  - A Windows PC to run the receiving server app and OBS Studio (optional).

## 🚀 How to Run

DreamStream is essentially a two-part application smartly bundled into a single Flutter codebase. When run on Windows, it dynamically acts as the Receiver Server. When run on Android, it acts as the Camera Client.

### 1. Start the Windows Receiver
Open your terminal in the project directory and compile the Windows app:
```bash
flutter run -d windows
```
Once it launches, it will sit idle and wait for an incoming socket connection. 

### 2. Start the Android Camera
Connect your Android phone to your PC (or ensure it's on the same Wi-Fi network) and run:
```bash
flutter run -d <your-android-device-id>
```

### 3. Pair and Stream!
1. On the Windows app, click the **QR Code icon** next to the IP address input field.
2. On your Android app, tap **"Scan QR to Pair"** and scan the code displayed on your monitor.
3. The phone will instantly handshake with the PC, and the Windows app will automatically click **"CONNECT"** for you.
4. *(Optional)*: Click the **Copy** button next to the OBS Media Source URL on your PC, paste it into an OBS Browser or Media source, and hit the **"Hide Preview"** (eye icon) in the app to save rendering resources!
