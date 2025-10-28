import 'dart:io' show Platform;  // ✅ ADDED for iOS detection
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  // IMPORTANT: Initialize bindings FIRST
  WidgetsFlutterBinding.ensureInitialized();

  // NOW you can call SystemChrome
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Twilio Video POC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TwilioVideoPage(),
    );
  }
}

class TwilioVideoPage extends StatefulWidget {
  const TwilioVideoPage({super.key});

  @override
  State<TwilioVideoPage> createState() => _TwilioVideoPageState();
}

class _TwilioVideoPageState extends State<TwilioVideoPage> {
  static const platform = MethodChannel('com.example.twilio_poc/video');

  String _status = 'Not Connected';
  bool _hasPermissions = false;
  bool _isConnected = false;
  bool _videoEnabled = true;
  bool _audioEnabled = true;
  bool _isConnecting = false;
  bool _showLocalVideo = false;
  bool _showRemoteVideo = false;

  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _roomController = TextEditingController(
      text: 'test_room'
  );

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    try {
      final bool hasPermissions = await platform.invokeMethod('checkPermissions');
      setState(() {
        _hasPermissions = hasPermissions;
        _status = hasPermissions ? 'Ready to connect' : 'Permissions required';
      });
    } catch (e) {
      _showError('Error checking permissions: $e');
    }
  }

  Future<void> _requestPermissions() async {
    try {
      final bool granted = await platform.invokeMethod('requestPermissions');
      setState(() {
        _hasPermissions = granted;
        _status = granted
            ? 'Permissions granted - Ready to connect'
            : 'Permissions denied - Please enable in settings';
      });

      if (!granted) {
        _showError('Please grant camera and microphone permissions in app settings');
      }
    } catch (e) {
      _showError('Error requesting permissions: $e');
    }
  }

  Future<void> _connectToRoom() async {
    if (_tokenController.text.isEmpty) {
      _showError('Please enter an access token');
      return;
    }

    if (_roomController.text.isEmpty) {
      _showError('Please enter a room name');
      return;
    }

    setState(() {
      _isConnecting = true;
      _status = 'Connecting...';
    });

    try {
      // Connect to room
      final String result = await platform.invokeMethod('connectToRoom', {
        'accessToken': _tokenController.text.trim(),
        'roomName': _roomController.text.trim(),
      });

      setState(() {
        _status = 'Connected to ${_roomController.text}';
        _isConnected = true;
        _isConnecting = false;
        _showLocalVideo = true;
        _showRemoteVideo = true;
      });

      _showSuccess('Connected! Check logs for connection status.');
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Connection failed: ${e.message}';
        _isConnected = false;
        _isConnecting = false;
      });
      _showError('Failed to connect: ${e.message}');
    }
  }

  Future<void> _disconnectFromRoom() async {
    try {
      await platform.invokeMethod('disconnectFromRoom');
      setState(() {
        _status = 'Disconnected';
        _isConnected = false;
        _videoEnabled = true;
        _audioEnabled = true;
        _showLocalVideo = false;
        _showRemoteVideo = false;
      });
      _showSuccess('Disconnected successfully');
    } catch (e) {
      _showError('Error disconnecting: $e');
    }
  }

  Future<void> _toggleVideo() async {
    try {
      final newState = !_videoEnabled;
      await platform.invokeMethod('toggleVideo', {'enabled': newState});
      setState(() {
        _videoEnabled = newState;
      });
    } catch (e) {
      _showError('Error toggling video: $e');
    }
  }

  Future<void> _toggleAudio() async {
    try {
      final newState = !_audioEnabled;
      await platform.invokeMethod('toggleAudio', {'enabled': newState});
      setState(() {
        _audioEnabled = newState;
      });
    } catch (e) {
      _showError('Error toggling audio: $e');
    }
  }

  Future<void> _switchCamera() async {
    try {
      await platform.invokeMethod('switchCamera');
      _showSuccess('Camera switched');
    } catch (e) {
      _showError('Error switching camera: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isConnected
          ? null
          : AppBar(
        title: const Text('Twilio Video POC'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isConnected ? _buildVideoCall() : _buildSetupScreen(),
    );
  }

  // ✅ UPDATED: Platform-specific video rendering
  Widget _buildVideoCall() {
    return Stack(
      children: [
        // Remote Video (Full Screen)
        if (_showRemoteVideo)
          Positioned.fill(
            child: Platform.isAndroid
                ? const AndroidView(
              viewType: 'twilio-video-view',
              creationParams: {'isLocal': false},
              creationParamsCodec: StandardMessageCodec(),
            )
                : const UiKitView(  // ✅ iOS uses UiKitView
              viewType: 'twilio-video-view',
              creationParams: {'isLocal': false},
              creationParamsCodec: StandardMessageCodec(),
            ),
          ),

        // Local Video (Picture-in-Picture)
        if (_showLocalVideo)
          Positioned(
            top: 48,
            right: 16,
            child: Container(
              width: 120,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Platform.isAndroid
                    ? const AndroidView(
                  viewType: 'twilio-video-view',
                  creationParams: {'isLocal': true},
                  creationParamsCodec: StandardMessageCodec(),
                )
                    : const UiKitView(  // ✅ iOS uses UiKitView
                  viewType: 'twilio-video-view',
                  creationParams: {'isLocal': true},
                  creationParamsCodec: StandardMessageCodec(),
                ),
              ),
            ),
          ),

        // Status Overlay
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _status,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),

        // Platform Indicator (for debugging)
        Positioned(
          top: 60,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Platform.isIOS ? Colors.blue.withValues(alpha: 0.7) : Colors.green.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              Platform.isIOS ? '📱 iOS' : '🤖 Android',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        // Control Buttons
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCallControl(
                icon: _videoEnabled ? Icons.videocam : Icons.videocam_off,
                label: 'Video',
                isActive: _videoEnabled,
                onPressed: _toggleVideo,
              ),
              _buildCallControl(
                icon: _audioEnabled ? Icons.mic : Icons.mic_off,
                label: 'Audio',
                isActive: _audioEnabled,
                onPressed: _toggleAudio,
              ),
              _buildCallControl(
                icon: Icons.cameraswitch,
                label: 'Switch',
                isActive: true,
                onPressed: _switchCamera,
                color: Colors.blue,
              ),
              _buildCallControl(
                icon: Icons.call_end,
                label: 'End',
                isActive: false,
                onPressed: _disconnectFromRoom,
                color: Colors.red,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCallControl({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final buttonColor = color ?? (isActive ? Colors.green : Colors.grey);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: buttonColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: Colors.white, size: 28),
            iconSize: 28,
            padding: const EdgeInsets.all(16),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSetupScreen() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Platform indicator at top
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: Platform.isIOS ? Colors.blue.shade100 : Colors.green.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                Platform.isIOS ? '📱 Running on iOS' : '🤖 Running on Android',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Platform.isIOS ? Colors.blue.shade900 : Colors.green.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Card(
              elevation: 4,
              color: _isConnected
                  ? Colors.green.shade50
                  : _isConnecting
                  ? Colors.orange.shade50
                  : Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Icon(
                      _isConnected
                          ? Icons.videocam
                          : _isConnecting
                          ? Icons.sync
                          : Icons.videocam_off,
                      size: 56,
                      color: _isConnected
                          ? Colors.green
                          : _isConnecting
                          ? Colors.orange
                          : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (!_hasPermissions) ...[
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.security, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            'Permissions Required',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        Platform.isIOS
                            ? 'This app needs camera and microphone permissions.'
                            : 'This app needs camera, microphone, and Bluetooth permissions.',
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _requestPermissions,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Grant Permissions'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_hasPermissions && !_isConnected) ...[
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Room Configuration',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _tokenController,
                        decoration: const InputDecoration(
                          labelText: 'Access Token',
                          hintText: 'Paste your Twilio access token',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.vpn_key),
                        ),
                        maxLines: 3,
                        enabled: !_isConnecting,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _roomController,
                        decoration: const InputDecoration(
                          labelText: 'Room Name',
                          hintText: 'Enter room name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.meeting_room),
                        ),
                        enabled: !_isConnecting,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _isConnecting ? null : _connectToRoom,
                        icon: _isConnecting
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white
                            ),
                          ),
                        )
                            : const Icon(Icons.video_call),
                        label: Text(_isConnecting ? 'Connecting...' : 'Join Call'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 56),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _roomController.dispose();
    super.dispose();
  }
}
