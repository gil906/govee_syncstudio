package com.goveesync.govee_lights_sync

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingDeepLink: String? = null
    private var platformChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        extractDeepLink(intent)?.let { pendingDeepLink = it }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.goveesync.govee_lights_sync/platform"
        )
        platformChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialDeepLink" -> {
                    val link = pendingDeepLink
                    pendingDeepLink = null
                    result.success(link)
                }
                "launchExternalUrl" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("INVALID_URL", "URL is required", null)
                    } else {
                        try {
                            val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addCategory(Intent.CATEGORY_BROWSABLE)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(browserIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LAUNCH_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractDeepLink(intent)?.let { link ->
            pendingDeepLink = link
            platformChannel?.invokeMethod("onDeepLink", link)
        }
    }

    private fun extractDeepLink(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        val scheme = data.scheme?.lowercase() ?: return null
        if (scheme == "goveesync" || scheme == "https" || scheme == "http") {
            return data.toString()
        }
        return null
    }
}
