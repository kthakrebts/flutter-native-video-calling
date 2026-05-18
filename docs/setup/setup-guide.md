# Infrastructure Setup & Local Deployment Guide

This document provides a comprehensive, step-by-step guide to configuring the external Twilio RTC infrastructure, preparing local Android and iOS native settings, running a local token generator server, and deploying the application.

---

## 1. Twilio Console Setup

The application relies on Twilio Video API services. You must register and acquire cryptographic keys to authorize mobile SDK clients.

### Step 1: Create a Twilio Account
- Go to the [Twilio Console](https://www.twilio.com/console) and create a free or paid developer account.
- Note your **Account SID** (e.g., `ACXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX`) on the main dashboard. This is your master account identifier.

### Step 2: Generate an API Key and API Secret
Access tokens are signed using a dedicated API Key to prevent exposing your master Account SID credentials on client devices.
1. Navigate to **Account ➔ API Keys & Tokens** or search for "API Keys".
2. Click **Create API Key**.
3. Set the friendly name (e.g., `flutter_native_video_calling_key`).
4. Set the key type to **Standard**.
5. Click **Create**.
6. **CRITICAL:** Copy the **SID** (starts with `SK...`) and the **Secret** immediately. The Secret will only be shown once.

### Step 3: Configure Room settings (Optional)
- Navigate to the **Video ➔ Rooms ➔ Settings** in the console.
- Configure default room topologies (Peer-to-Peer vs Group vs Go) depending on your participant scaling requirements. For local testing, **Group** or **Peer-to-Peer** is recommended.

---

## 2. Generating Access Tokens (JWT)

For security, mobile clients should never generate Access Tokens locally. Instead, a backend server must generate and sign tokens using your Twilio credentials.

### Example Node.js Token Server Implementation
Below is a production-ready Node.js Express server code to generate and serve tokens for the Flutter app.

```javascript
const express = require('express');
const twilio = require('twilio');

const app = express();
app.use(express.json());

const AccessToken = twilio.jwt.AccessToken;
const VideoGrant = AccessToken.VideoGrant;

// Credentials (load from environment variables)
const ACCOUNT_SID = process.env.TWILIO_ACCOUNT_SID;
const API_KEY_SID = process.env.TWILIO_API_KEY_SID;
const API_KEY_SECRET = process.env.TWILIO_API_KEY_SECRET;

app.get('/token', (req, res) => {
  const identity = req.query.identity || `user-${Math.floor(Math.random() * 100000)}`;
  const roomName = req.query.roomName || 'default_room';

  if (!ACCOUNT_SID || !API_KEY_SID || !API_KEY_SECRET) {
    return res.status(500).json({ error: "Missing Twilio credentials on server" });
  }

  // Create access token
  const token = new AccessToken(
    ACCOUNT_SID,
    API_KEY_SID,
    API_KEY_SECRET,
    { identity: identity, ttl: 3600 } // 1 hour expiration
  );

  // Grant access to Video Room
  const videoGrant = new VideoGrant({ room: roomName });
  token.addGrant(videoGrant);

  // Return token payload
  res.json({
    identity: identity,
    roomName: roomName,
    token: token.toJwt()
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 Token server running on port ${PORT}`));
```

---

## 3. Platform Configurations

### 🤖 Android Native Configuration

#### 1. Add Hardware and Software Permissions
Open `android/app/src/main/AndroidManifest.xml` and verify that the following nodes are declared as children of the `<manifest>` tag:

```xml
<!-- Media Hardware Permissions -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />

<!-- Bluetooth Audio Routing Permissions (API 31+) -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Notification Foreground Services (API 33+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Manifest Hardware Requirements -->
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
```

#### 2. Configure Proguard rules (Release Mode)
If your app-level Gradle build file enables code obfuscation (`isMinifyEnabled = true`), add the following rules to your `android/app/proguard-rules.pro` file to prevent the compiler from stripping or obfuscating Twilio and WebRTC classes:

```proguard
# Keep Twilio Video Classes
-keep class com.twilio.video.** { *; }
-keep class tvi.webrtc.** { *; }

# Keep interface classes
-keep interface com.twilio.video.** { *; }

# Prevent log stripping if needed
-dontwarn com.twilio.video.**
-dontwarn tvi.webrtc.**
```

---

### 🍏 iOS Native Configuration (Infrastructure Reference)

To deploy the Twilio RTC infrastructure on iOS, apply these configuration steps inside your Xcode workspace.

#### 1. Setup Info.plist Permissions
Open your `ios/Runner/Info.plist` file and add the description keys explaining why the application requests access to the device's hardware:

```xml
<key>NSCameraUsageDescription</key>
<string>This application requires access to the camera to transmit your local video stream to other participants in the video call.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This application requires access to the microphone to capture and transmit your voice to other participants in the video call.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>This application requires local network permissions to discover nearby media nodes and establish secure direct peer-to-peer WebRTC connections.</string>
```

#### 2. Configure Podfile & SDK Import
The Twilio Video iOS SDK is imported via CocoaPods. Open your `ios/Podfile` and verify the deployment target and dependencies:

```ruby
platform :ios, '13.0'

target 'Runner' do
  use_frameworks!
  use_native_modules!

  # Import Twilio Video iOS SDK
  pod 'TwilioVideo', '~> 5.4'
end
```
Run `pod install` inside the `ios/` directory to fetch the native iOS libraries.

---

## 4. Local Development Execution

Once the Twilio console, the token server, and native platform permissions are configured, you can launch the application:

1. **Start your token server** locally or verify you have generated a token.
2. **Open the emulator** or connect a physical debugging device (strongly recommended for testing camera hardware).
3. **Execute the run command:**
   ```bash
   flutter pub get
   flutter run --debug
   ```
4. **Testing Call Connectivity:**
   - On the mobile client, paste the generated token into the **Access Token** field.
   - Enter your target room name (e.g., `test_room`).
   - Tap **Join Call**.
   - Use a second device or the Twilio WebRTC Portal to join the same room (`test_room`) to verify bi-directional audio/video transport.
