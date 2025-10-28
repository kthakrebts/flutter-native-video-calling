package com.example.twilio_poc

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.twilio.video.*
import tvi.webrtc.Camera2Enumerator

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.twilio_poc/video"
    private val TAG = "TwilioPOC"
    private val PERMISSION_REQUEST_CODE = 100

    private var room: Room? = null
    private var localVideoTrack: LocalVideoTrack? = null
    private var localAudioTrack: LocalAudioTrack? = null
    private var methodResult: MethodChannel.Result? = null

    // Video views for rendering
    private var localVideoView: com.twilio.video.VideoView? = null
    private var remoteVideoView: com.twilio.video.VideoView? = null
    private val remoteParticipants = mutableMapOf<String, RemoteParticipant>()

    // Camera tracking - ADDED
    private var currentCameraId: String? = null
    private var isUsingFrontCamera = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            enableEdgeToEdge()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register video view factory
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "twilio-video-view",
                TwilioVideoViewFactory(this)
            )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermissions" -> {
                        result.success(hasPermissions())
                    }
                    "requestPermissions" -> {
                        methodResult = result
                        requestPermissions()
                    }
                    "connectToRoom" -> {
                        val accessToken = call.argument<String>("accessToken")
                        val roomName = call.argument<String>("roomName")

                        if (accessToken == null || roomName == null) {
                            result.error("INVALID_ARGUMENTS",
                                "AccessToken and RoomName are required", null)
                            return@setMethodCallHandler
                        }

                        if (!hasPermissions()) {
                            result.error("PERMISSION_DENIED",
                                "Camera and microphone permissions required", null)
                            return@setMethodCallHandler
                        }

                        connectToRoom(accessToken, roomName, result)
                    }
                    "disconnectFromRoom" -> {
                        disconnectFromRoom()
                        result.success("Disconnected successfully")
                    }
                    "toggleVideo" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        localVideoTrack?.enable(enabled)
                        result.success("Video ${if (enabled) "enabled" else "disabled"}")
                    }
                    "toggleAudio" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        localAudioTrack?.enable(enabled)
                        result.success("Audio ${if (enabled) "enabled" else "disabled"}")
                    }
                    "switchCamera" -> {
                        switchCamera()
                        result.success("Camera switched")
                    }
//                    "initLocalVideoView" -> {
////                        initLocalVideoView()
//                        result.success(null)
//                    }
//                    "initRemoteVideoView" -> {
////                        initRemoteVideoView()
//                        result.success(null)
//                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

//    private fun initLocalVideoView() {
//        runOnUiThread {
//            if (localVideoView == null) {
//                localVideoView = com.twilio.video.VideoView(this)
//                localVideoView?.mirror = true // Mirror for front camera
//
//                // Attach local video track if it exists
//                localVideoTrack?.addSink(localVideoView!!)
//                Log.d(TAG, "Local video view initialized and track attached")
//            }
//        }
//    }

//    private fun initRemoteVideoView() {
//        runOnUiThread {
//            if (remoteVideoView == null) {
//                remoteVideoView = com.twilio.video.VideoView(this)
//                Log.d(TAG, "Remote video view initialized")
//            }
//        }
//    }

    // Add these methods to MainActivity class
    fun setLocalVideoView(view: VideoView) {
        localVideoView = view
        // Attach existing track if available
        localVideoTrack?.addSink(view)
        Log.d(TAG, "✅ Local VideoView registered and track attached")
    }

    fun clearLocalVideoView() {
        localVideoView?.let { view ->
            localVideoTrack?.removeSink(view)
        }
        localVideoView = null
        Log.d(TAG, "🗑️ Local VideoView cleared")
    }

    fun setRemoteVideoView(view: VideoView) {
        remoteVideoView = view
        // Attach existing remote tracks if available
        remoteParticipants.values.forEach { participant ->
            participant.remoteVideoTracks.forEach { publication ->
                publication.remoteVideoTrack?.addSink(view)
            }
        }
        Log.d(TAG, "✅ Remote VideoView registered and tracks attached")
    }

    fun clearRemoteVideoView() {
        remoteVideoView?.let { view ->
            remoteParticipants.values.forEach { participant ->
                participant.remoteVideoTracks.forEach { publication ->
                    publication.remoteVideoTrack?.removeSink(view)
                }
            }
        }
        remoteVideoView = null
        Log.d(TAG, "🗑️ Remote VideoView cleared")
    }


    private fun hasPermissions(): Boolean {
        val requiredPermissions = mutableListOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requiredPermissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requiredPermissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        return requiredPermissions.all { permission ->
            ContextCompat.checkSelfPermission(this, permission) ==
                    PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestPermissions() {
        val requiredPermissions = mutableListOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requiredPermissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requiredPermissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        ActivityCompat.requestPermissions(
            this,
            requiredPermissions.toTypedArray(),
            PERMISSION_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            methodResult?.success(allGranted)
            methodResult = null
        }
    }

    private fun connectToRoom(
        accessToken: String,
        roomName: String,
        result: MethodChannel.Result
    ) {
        try {
            // Create local audio track
            localAudioTrack = LocalAudioTrack.create(this, true, "microphone")

            // Create local video track
            val camera2Enumerator = Camera2Enumerator(this)

            // Find and use front camera by default - UPDATED
            currentCameraId = camera2Enumerator.deviceNames.firstOrNull {
                camera2Enumerator.isFrontFacing(it)
            }

            if (currentCameraId != null) {
                val cameraCapturer = Camera2Capturer(this, currentCameraId!!)
                localVideoTrack = LocalVideoTrack.create(
                    this,
                    true,
                    cameraCapturer,
                    "camera"
                )

                // Track that we're using front camera - ADDED
                isUsingFrontCamera = true

                // Attach local video to view if it exists
                localVideoView?.let { view ->
                    localVideoTrack?.addSink(view)
                    view.mirror = true // Mirror for front camera
                    Log.d(TAG, "Local video track attached to view (Front camera)")
                }
            } else {
                Log.e(TAG, "No camera found on device")
            }

            // Build connection options
            val connectOptions = ConnectOptions.Builder(accessToken)
                .roomName(roomName)
                .apply {
                    localAudioTrack?.let { audioTracks(listOf(it)) }
                    localVideoTrack?.let { videoTracks(listOf(it)) }
                }
                .enableAutomaticSubscription(true)
                .enableNetworkQuality(true)
                .networkQualityConfiguration(
                    NetworkQualityConfiguration(
                        NetworkQualityVerbosity.NETWORK_QUALITY_VERBOSITY_MINIMAL,
                        NetworkQualityVerbosity.NETWORK_QUALITY_VERBOSITY_MINIMAL
                    )
                )
                .build()

            // Connect to room
            room = Video.connect(this, connectOptions, roomListener())

            Log.d(TAG, "Connecting to room: $roomName")
            result.success("Connecting to $roomName...")

        } catch (e: Exception) {
            Log.e(TAG, "Error connecting to room", e)
            result.error("CONNECTION_ERROR", e.message, null)
        }
    }

    private fun roomListener(): Room.Listener {
        return object : Room.Listener {
            override fun onConnected(room: Room) {
                Log.d(TAG, "✅ Connected to room: ${room.name}")
                Log.d(TAG, "Room SID: ${room.sid}")
                Log.d(TAG, "Local participant: ${room.localParticipant?.identity}")
                Log.d(TAG, "Remote participants: ${room.remoteParticipants.size}")

                // Add listeners to existing participants
                room.remoteParticipants.forEach { participant ->
                    addRemoteParticipant(participant)
                }
            }

            override fun onConnectFailure(room: Room, exception: TwilioException) {
                Log.e(TAG, "❌ Failed to connect to room", exception)
                Log.e(TAG, "Error code: ${exception.code}")
                Log.e(TAG, "Error message: ${exception.message}")
            }

            override fun onDisconnected(room: Room, exception: TwilioException?) {
                Log.d(TAG, "Disconnected from room: ${room.name}")
                localVideoView?.let { view ->
                    localVideoTrack?.removeSink(view)
                }
                remoteParticipants.clear()
            }

            override fun onParticipantConnected(room: Room, participant: RemoteParticipant) {
                Log.d(TAG, "👤 Participant connected: ${participant.identity}")
                addRemoteParticipant(participant)
            }

            override fun onParticipantDisconnected(
                room: Room,
                participant: RemoteParticipant
            ) {
                Log.d(TAG, "👤 Participant disconnected: ${participant.identity}")
                remoteParticipants.remove(participant.identity)
            }

            override fun onRecordingStarted(room: Room) {
                Log.d(TAG, "🔴 Recording started")
            }

            override fun onRecordingStopped(room: Room) {
                Log.d(TAG, "⭕ Recording stopped")
            }

            override fun onReconnecting(room: Room, exception: TwilioException) {
                Log.d(TAG, "🔄 Reconnecting to room...")
            }

            override fun onReconnected(room: Room) {
                Log.d(TAG, "✅ Reconnected to room")
            }
        }
    }

    private fun addRemoteParticipant(participant: RemoteParticipant) {
        remoteParticipants[participant.identity] = participant
        participant.setListener(remoteParticipantListener())

        // Subscribe to already published tracks
        participant.remoteVideoTracks.forEach { publication ->
            publication.remoteVideoTrack?.let { track ->
                addRemoteVideoTrack(track)
            }
        }
    }

    private fun addRemoteVideoTrack(videoTrack: RemoteVideoTrack) {
        runOnUiThread {
            remoteVideoView?.let { view ->
                videoTrack.addSink(view)
                Log.d(TAG, "🎥 Remote video track attached to view")
            }
        }
    }

    private fun remoteParticipantListener(): RemoteParticipant.Listener {
        return object : RemoteParticipant.Listener {
            override fun onAudioTrackPublished(
                participant: RemoteParticipant,
                publication: RemoteAudioTrackPublication
            ) {
                Log.d(TAG, "🔊 Audio track published by ${participant.identity}")
            }

            override fun onAudioTrackUnpublished(
                participant: RemoteParticipant,
                publication: RemoteAudioTrackPublication
            ) {
                Log.d(TAG, "🔇 Audio track unpublished by ${participant.identity}")
            }

            override fun onVideoTrackPublished(
                participant: RemoteParticipant,
                publication: RemoteVideoTrackPublication
            ) {
                Log.d(TAG, "📹 Video track published by ${participant.identity}")
            }

            override fun onVideoTrackUnpublished(
                participant: RemoteParticipant,
                publication: RemoteVideoTrackPublication
            ) {
                Log.d(TAG, "📴 Video track unpublished by ${participant.identity}")
            }

            override fun onDataTrackPublished(
                participant: RemoteParticipant,
                publication: RemoteDataTrackPublication
            ) {
                Log.d(TAG, "📊 Data track published by ${participant.identity}")
            }

            override fun onDataTrackUnpublished(
                participant: RemoteParticipant,
                publication: RemoteDataTrackPublication
            ) {
                Log.d(TAG, "Data track unpublished by ${participant.identity}")
            }

            override fun onAudioTrackSubscribed(
                participant: RemoteParticipant,
                publication: RemoteAudioTrackPublication,
                track: RemoteAudioTrack
            ) {
                Log.d(TAG, "✅ Audio track subscribed from ${participant.identity}")
            }

            override fun onAudioTrackUnsubscribed(
                participant: RemoteParticipant,
                publication: RemoteAudioTrackPublication,
                track: RemoteAudioTrack
            ) {
                Log.d(TAG, "Audio track unsubscribed from ${participant.identity}")
            }

            override fun onAudioTrackSubscriptionFailed(
                participant: RemoteParticipant,
                publication: RemoteAudioTrackPublication,
                exception: TwilioException
            ) {
                Log.e(TAG, "❌ Failed to subscribe to audio: ${exception.message}")
            }

            override fun onVideoTrackSubscribed(
                participant: RemoteParticipant,
                publication: RemoteVideoTrackPublication,
                track: RemoteVideoTrack
            ) {
                Log.d(TAG, "✅ Video track subscribed from ${participant.identity}")
                addRemoteVideoTrack(track)
            }

            override fun onVideoTrackUnsubscribed(
                participant: RemoteParticipant,
                publication: RemoteVideoTrackPublication,
                track: RemoteVideoTrack
            ) {
                Log.d(TAG, "Video track unsubscribed from ${participant.identity}")
                runOnUiThread {
                    remoteVideoView?.let { view ->
                        track.removeSink(view)
                    }
                }
            }

            override fun onVideoTrackSubscriptionFailed(
                participant: RemoteParticipant,
                publication: RemoteVideoTrackPublication,
                exception: TwilioException
            ) {
                Log.e(TAG, "❌ Failed to subscribe to video: ${exception.message}")
            }

            override fun onDataTrackSubscribed(
                participant: RemoteParticipant,
                publication: RemoteDataTrackPublication,
                track: RemoteDataTrack
            ) {
                Log.d(TAG, "Data track subscribed from ${participant.identity}")
            }

            override fun onDataTrackUnsubscribed(
                participant: RemoteParticipant,
                publication: RemoteDataTrackPublication,
                track: RemoteDataTrack
            ) {
                Log.d(TAG, "Data track unsubscribed from ${participant.identity}")
            }

            override fun onDataTrackSubscriptionFailed(
                participant: RemoteParticipant,
                publication: RemoteDataTrackPublication,
                exception: TwilioException
            ) {
                Log.e(TAG, "Failed to subscribe to data: ${exception.message}")
            }

            override fun onAudioTrackEnabled(
                participant: RemoteParticipant,
                publication: RemoteAudioTrackPublication
            ) {
                Log.d(TAG, "🔊 Audio enabled by ${participant.identity}")
            }

            override fun onAudioTrackDisabled(
                participant: RemoteParticipant,
                publication: RemoteAudioTrackPublication
            ) {
                Log.d(TAG, "🔇 Audio disabled by ${participant.identity}")
            }

            override fun onVideoTrackEnabled(
                participant: RemoteParticipant,
                publication: RemoteVideoTrackPublication
            ) {
                Log.d(TAG, "📹 Video enabled by ${participant.identity}")
            }

            override fun onVideoTrackDisabled(
                participant: RemoteParticipant,
                publication: RemoteVideoTrackPublication
            ) {
                Log.d(TAG, "📴 Video disabled by ${participant.identity}")
            }

            override fun onNetworkQualityLevelChanged(
                participant: RemoteParticipant,
                networkQualityLevel: NetworkQualityLevel
            ) {
                Log.d(TAG, "📶 Network quality for ${participant.identity}: $networkQualityLevel")
            }
        }
    }

    // FIXED switchCamera method - COMPLETE REPLACEMENT
    private fun switchCamera() {
        try {
            val camera2Enumerator = Camera2Enumerator(this)
            val cameraCapturer = localVideoTrack?.videoCapturer as? Camera2Capturer

            if (cameraCapturer == null) {
                Log.e(TAG, "❌ Camera capturer is null, cannot switch")
                return
            }

            // Find the opposite camera
            val newCameraId = if (isUsingFrontCamera) {
                // Currently front camera, find back camera
                camera2Enumerator.deviceNames.firstOrNull { cameraId ->
                    !camera2Enumerator.isFrontFacing(cameraId)
                }
            } else {
                // Currently back camera, find front camera
                camera2Enumerator.deviceNames.firstOrNull { cameraId ->
                    camera2Enumerator.isFrontFacing(cameraId)
                }
            }

            if (newCameraId != null && newCameraId != currentCameraId) {
                // Switch to new camera
                cameraCapturer.switchCamera(newCameraId)
                currentCameraId = newCameraId
                isUsingFrontCamera = !isUsingFrontCamera

                // Update mirror setting (mirror only for front camera)
                localVideoView?.mirror = isUsingFrontCamera

                val cameraType = if (isUsingFrontCamera) "Front" else "Back"
                Log.d(TAG, "🔄 Camera switched to: $cameraType camera")
            } else {
                Log.w(TAG, "⚠️ No alternative camera available")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error switching camera: ${e.message}", e)
        }
    }

    private fun disconnectFromRoom() {
        // Remove video sinks
        localVideoView?.let { view ->
            localVideoTrack?.removeSink(view)
        }

        remoteVideoView?.let { view ->
            remoteParticipants.values.forEach { participant ->
                participant.remoteVideoTracks.forEach { publication ->
                    publication.remoteVideoTrack?.removeSink(view)
                }
            }
        }

        // Disconnect and cleanup
        room?.disconnect()
        room = null

        localAudioTrack?.release()
        localAudioTrack = null

        localVideoTrack?.release()
        localVideoTrack = null

        remoteParticipants.clear()

        Log.d(TAG, "🧹 Cleaned up all tracks and resources")
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun enableEdgeToEdge() {
        window.setDecorFitsSystemWindows(false)
    }

    override fun onDestroy() {
        disconnectFromRoom()
        localVideoView = null
        remoteVideoView = null
        super.onDestroy()
    }
}
