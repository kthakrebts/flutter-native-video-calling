import UIKit
import Flutter
import TwilioVideo

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    private let CHANNEL = "com.example.twilio_poc/video"
    
    // Twilio Video properties
    private var room: Room?
    private var camera: CameraSource?
    private var localVideoTrack: LocalVideoTrack?
    private var localAudioTrack: LocalAudioTrack?
    private var remoteParticipant: RemoteParticipant?
    
    // Video views
    private var localVideoView: VideoView?
    private var remoteVideoView: VideoView?
    
    // Camera state
    private var isUsingFrontCamera = true
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        
        // ✅ Register Platform View Factory for video rendering
        let videoViewFactory = TwilioVideoViewFactory(messenger: controller.binaryMessenger, appDelegate: self)
        registrar(forPlugin: "TwilioVideoView")?.register(
            videoViewFactory,
            withId: "twilio-video-view"
        )
        
        // Setup Twilio Video Channel
        let videoChannel = FlutterMethodChannel(
            name: CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )
        
        videoChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            guard let self = self else { return }
            
            switch call.method {
            case "checkPermissions":
                self.checkPermissions(result: result)
                
            case "requestPermissions":
                self.requestPermissions(result: result)
                
            case "connectToRoom":
                guard let args = call.arguments as? [String: Any],
                      let accessToken = args["accessToken"] as? String,
                      let roomName = args["roomName"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENTS",
                                      message: "AccessToken and RoomName required",
                                      details: nil))
                    return
                }
                self.connectToRoom(accessToken: accessToken, roomName: roomName, result: result)
                
            case "disconnectFromRoom":
                self.disconnectFromRoom()
                result("Disconnected successfully")
                
            case "toggleVideo":
                guard let args = call.arguments as? [String: Any],
                      let enabled = args["enabled"] as? Bool else {
                    result(FlutterError(code: "INVALID_ARGUMENTS",
                                      message: "enabled parameter required",
                                      details: nil))
                    return
                }
                self.localVideoTrack?.isEnabled = enabled
                result("Video \(enabled ? "enabled" : "disabled")")
                
            case "toggleAudio":
                guard let args = call.arguments as? [String: Any],
                      let enabled = args["enabled"] as? Bool else {
                    result(FlutterError(code: "INVALID_ARGUMENTS",
                                      message: "enabled parameter required",
                                      details: nil))
                    return
                }
                self.localAudioTrack?.isEnabled = enabled
                result("Audio \(enabled ? "enabled" : "disabled")")
                
            case "switchCamera":
                self.flipCamera()
                result("Camera switched")
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - Video View Management
    
    func setLocalVideoView(_ view: VideoView) {
        localVideoView = view
        localVideoTrack?.addRenderer(view)  // ✅ FIXED: addRenderer instead of addVideoSink
        print("✅ iOS: Local VideoView registered")
    }
    
    func setRemoteVideoView(_ view: VideoView) {
        remoteVideoView = view
        // Attach existing remote tracks if available
        remoteParticipant?.remoteVideoTracks.forEach { publication in
            if let remoteVideoTrack = publication.remoteTrack {
                remoteVideoTrack.addRenderer(view)  // ✅ FIXED: addRenderer
            }
        }
        print("✅ iOS: Remote VideoView registered")
    }
    
    // MARK: - Permission Methods
    
    private func checkPermissions(result: @escaping FlutterResult) {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        let hasPermissions = cameraStatus == .authorized && microphoneStatus == .authorized
        result(hasPermissions)
    }
    
    private func requestPermissions(result: @escaping FlutterResult) {
        var cameraGranted = false
        var microphoneGranted = false
        
        let group = DispatchGroup()
        
        // Request camera permission
        group.enter()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            cameraGranted = granted
            group.leave()
        }
        
        // Request microphone permission
        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            microphoneGranted = granted
            group.leave()
        }
        
        group.notify(queue: .main) {
            result(cameraGranted && microphoneGranted)
        }
    }
    
    // MARK: - Twilio Video Methods
    
    private func connectToRoom(accessToken: String, roomName: String, result: @escaping FlutterResult) {
        // Setup local media
        setupLocalMedia()
        
        // Connect to room
        let connectOptions = ConnectOptions(token: accessToken) { builder in
            builder.roomName = roomName
            
            if let localVideoTrack = self.localVideoTrack {
                builder.videoTracks = [localVideoTrack]
            }
            
            if let localAudioTrack = self.localAudioTrack {
                builder.audioTracks = [localAudioTrack]
            }
        }
        
        room = TwilioVideoSDK.connect(options: connectOptions, delegate: self)
        
        print("📹 iOS: Connecting to room: \(roomName)")
        result("Connecting to \(roomName)...")
    }
    
    private func setupLocalMedia() {
        // Setup local audio
        localAudioTrack = LocalAudioTrack(options: nil, enabled: true, name: "microphone")
        
        // Setup local video with front camera
        if let frontCamera = CameraSource.captureDevice(position: .front) {
            camera = CameraSource(delegate: self)
            localVideoTrack = LocalVideoTrack(source: camera!, enabled: true, name: "camera")
            
            // Attach to view if already created
            if let view = localVideoView {
                localVideoTrack?.addRenderer(view)  // ✅ FIXED: addRenderer
            }
            
            // Start capturing
            camera?.startCapture(device: frontCamera) { (captureDevice, videoFormat, error) in
                if let error = error {
                    print("❌ iOS: Camera start error: \(error.localizedDescription)")
                } else {
                    print("✅ iOS: Camera started: \(captureDevice.localizedName)")
                }
            }
        }
    }
    
    private func flipCamera() {
        guard let camera = camera else { return }
        
        var newDevice: AVCaptureDevice?
        
        if isUsingFrontCamera {
            newDevice = CameraSource.captureDevice(position: .back)
        } else {
            newDevice = CameraSource.captureDevice(position: .front)
        }
        
        if let newDevice = newDevice {
            camera.selectCaptureDevice(newDevice) { (captureDevice, videoFormat, error) in
                if let error = error {
                    print("❌ iOS: Error switching camera: \(error.localizedDescription)")
                } else {
                    self.isUsingFrontCamera = !self.isUsingFrontCamera
                    print("🔄 iOS: Camera switched to: \(self.isUsingFrontCamera ? "front" : "back")")
                }
            }
        }
    }
    
    private func disconnectFromRoom() {
        room?.disconnect()
        
        if let camera = camera {
            camera.stopCapture()
            self.camera = nil
        }
        
        localVideoTrack = nil
        localAudioTrack = nil
        room = nil
        
        print("🧹 iOS: Disconnected and cleaned up")
    }
}

// MARK: - RoomDelegate

extension AppDelegate: RoomDelegate {
    func roomDidConnect(room: Room) {
        print("✅ iOS: Connected to room: \(room.name)")
        print("iOS: Room SID: \(room.sid)")
        print("iOS: Local participant: \(room.localParticipant?.identity ?? "Unknown")")
        
        // Subscribe to existing participants
        room.remoteParticipants.forEach { participant in
            participant.delegate = self
        }
    }
    
    func roomDidFailToConnect(room: Room, error: Error) {
        print("❌ iOS: Failed to connect to room: \(error.localizedDescription)")
    }
    
    func roomDidDisconnect(room: Room, error: Error?) {
        print("iOS: Disconnected from room: \(room.name)")
        if let error = error {
            print("iOS: Error: \(error.localizedDescription)")
        }
    }
    
    func participantDidConnect(room: Room, participant: RemoteParticipant) {
        print("👤 iOS: Participant connected: \(participant.identity)")
        participant.delegate = self
    }
    
    func participantDidDisconnect(room: Room, participant: RemoteParticipant) {
        print("👤 iOS: Participant disconnected: \(participant.identity)")
    }
}

// MARK: - RemoteParticipantDelegate

extension AppDelegate: RemoteParticipantDelegate {
    func remoteParticipantDidPublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        print("📹 iOS: Video track published by \(participant.identity)")
    }
    
    func remoteParticipantDidUnpublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        print("📴 iOS: Video track unpublished by \(participant.identity)")
    }
    
    func remoteParticipantDidPublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        print("🔊 iOS: Audio track published by \(participant.identity)")
    }
    
    func remoteParticipantDidUnpublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        print("🔇 iOS: Audio track unpublished by \(participant.identity)")
    }
    
    func didSubscribeToVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        print("✅ iOS: Subscribed to video track from \(participant.identity)")
        remoteParticipant = participant
        
        // Attach to remote video view if available
        if let view = remoteVideoView {
            videoTrack.addRenderer(view)  // ✅ FIXED: addRenderer
        }
    }
    
    func didUnsubscribeFromVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        print("iOS: Unsubscribed from video track from \(participant.identity)")
    }
    
    func didSubscribeToAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        print("✅ iOS: Subscribed to audio track from \(participant.identity)")
    }
    
    func didUnsubscribeFromAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        print("iOS: Unsubscribed from audio track from \(participant.identity)")
    }
    
    func didFailToSubscribeToAudioTrack(publication: RemoteAudioTrackPublication, error: Error, participant: RemoteParticipant) {
        print("❌ iOS: Failed to subscribe to audio: \(error.localizedDescription)")
    }
    
    func didFailToSubscribeToVideoTrack(publication: RemoteVideoTrackPublication, error: Error, participant: RemoteParticipant) {
        print("❌ iOS: Failed to subscribe to video: \(error.localizedDescription)")
    }
}

// MARK: - CameraSourceDelegate

extension AppDelegate: CameraSourceDelegate {
    func cameraSourceDidFailWithError(source: CameraSource, error: Error) {
        print("❌ iOS: Camera source error: \(error.localizedDescription)")
    }
}

// MARK: - Platform View Factory

class TwilioVideoViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger
    private weak var appDelegate: AppDelegate?
    
    init(messenger: FlutterBinaryMessenger, appDelegate: AppDelegate) {
        self.messenger = messenger
        self.appDelegate = appDelegate
        super.init()
    }
    
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        let params = args as? [String: Any]
        let isLocal = params?["isLocal"] as? Bool ?? false
        
        return TwilioPlatformView(
            frame: frame,
            viewId: viewId,
            isLocal: isLocal,
            appDelegate: appDelegate
        )
    }
    
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

class TwilioPlatformView: NSObject, FlutterPlatformView {
    private var videoView: VideoView
    private weak var appDelegate: AppDelegate?
    private let isLocal: Bool
    
    init(frame: CGRect, viewId: Int64, isLocal: Bool, appDelegate: AppDelegate?) {
        self.isLocal = isLocal
        self.appDelegate = appDelegate
        self.videoView = VideoView(frame: frame)
        
        super.init()
        
        // Configure video view
        videoView.contentMode = .scaleAspectFill
        videoView.shouldMirror = isLocal  // Mirror local video
        
        // Register with AppDelegate
        if isLocal {
            appDelegate?.setLocalVideoView(videoView)
            print("📹 iOS: Created LOCAL video view")
        } else {
            appDelegate?.setRemoteVideoView(videoView)
            print("📹 iOS: Created REMOTE video view")
        }
    }
    
    func view() -> UIView {
        return videoView
    }
}
