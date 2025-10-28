package com.example.twilio_poc

import android.content.Context
import android.util.Log
import android.view.View
import com.twilio.video.VideoView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class TwilioVideoViewFactory(
    private val mainActivity: MainActivity
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    private val TAG = "TwilioVideoFactory"

    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        // Parse arguments to determine if this is local or remote view
        val creationParams = args as? Map<*, *>
        val isLocal = creationParams?.get("isLocal") as? Boolean ?: false

        Log.d(TAG, "Creating ${if (isLocal) "LOCAL" else "REMOTE"} video view with ID: $viewId")

        return if (isLocal) {
            TwilioLocalVideoView(context!!, mainActivity)
        } else {
            TwilioRemoteVideoView(context!!, mainActivity)
        }
    }
}

class TwilioLocalVideoView(
    context: Context,
    private val mainActivity: MainActivity
) : PlatformView {
    private val TAG = "TwilioLocalView"
    private val videoView: VideoView = VideoView(context).apply {
        mirror = true // Mirror for front camera (selfie mode)
    }

    init {
        Log.d(TAG, "📹 Local video view created")
        // Register this view with MainActivity so it can attach video tracks
        mainActivity.setLocalVideoView(videoView)
    }

    override fun getView(): View {
        return videoView
    }

    override fun dispose() {
        Log.d(TAG, "🗑️ Local video view disposed")
        mainActivity.clearLocalVideoView()
    }
}

class TwilioRemoteVideoView(
    context: Context,
    private val mainActivity: MainActivity
) : PlatformView {
    private val TAG = "TwilioRemoteView"
    private val videoView: VideoView = VideoView(context).apply {
        mirror = false // Don't mirror remote video
    }

    init {
        Log.d(TAG, "📹 Remote video view created")
        // Register this view with MainActivity so it can attach video tracks
        mainActivity.setRemoteVideoView(videoView)
    }

    override fun getView(): View {
        return videoView
    }

    override fun dispose() {
        Log.d(TAG, "🗑️ Remote video view disposed")
        mainActivity.clearRemoteVideoView()
    }
}
