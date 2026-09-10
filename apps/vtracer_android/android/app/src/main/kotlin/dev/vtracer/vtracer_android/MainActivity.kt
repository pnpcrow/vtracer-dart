package dev.vtracer.vtracer_android

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/// Host activity for the Flutter app.
///
/// The manifest declares this activity as a handler for `ACTION_VIEW` and
/// `ACTION_SEND` intents with `image/*` MIME types, so VTracer shows up in
/// the system share sheet and "open with" choosers. Incoming images are
/// handed to Dart over the `vtracer_android/platform` channel: cold starts
/// buffer the payload for `getInitialImage`, warm starts push it as
/// `onImageIntent`.
///
/// The traced SVG is saved into the public Downloads collection through
/// MediaStore — the app declares no storage permission of any kind.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /// Buffered payload for an image intent, kept until Dart pulls it with
    /// `getInitialImage`.
    private var pendingIntentPayload: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).also { channel -> channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialImage" -> {
                    val payload = pendingIntentPayload ?: extractImagePayload(intent)
                    pendingIntentPayload = null
                    // Consume the launch intent so a later pull (e.g. after
                    // the activity is recreated) does not re-deliver the
                    // same image.
                    intent.replaceExtras(Bundle())
                    intent.setDataAndType(null, null)
                    result.success(payload)
                }
                "saveSvgToDownloads" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val fileName = call.argument<String>("fileName")
                    if (bytes == null || fileName == null) {
                        result.error("bad_args", "bytes and fileName are required", null)
                    } else {
                        try {
                            result.success(saveToDownloads(bytes, fileName))
                        } catch (e: Exception) {
                            result.error("save_failed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        } }
        // Cold start via VIEW/SEND: buffer for the first getInitialImage.
        extractImagePayload(intent)?.let { pendingIntentPayload = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Warm start: push straight to Dart. If the Dart side has not
        // registered its handler yet, buffer the payload for the next
        // getInitialImage call instead of dropping it.
        extractImagePayload(intent)?.let { payload ->
            channel?.invokeMethod("onImageIntent", payload, object : MethodChannel.Result {
                override fun success(result: Any?) {}
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    pendingIntentPayload = payload
                }
                override fun notImplemented() {
                    pendingIntentPayload = payload
                }
            })
        }
    }

    /// Reads the image handed over by the sending app (its content URI) and
    /// copies the bytes — the URI grant lasts only for this activity's
    /// lifetime, so nothing else is kept.
    private fun extractImagePayload(received: Intent?): Map<String, Any?>? {
        if (received == null) return null
        val type = received.type ?: received.resolveType(this) ?: return null
        if (!type.startsWith("image/")) return null
        val uri: Uri = when (received.action) {
            Intent.ACTION_VIEW -> received.data
            Intent.ACTION_SEND -> received.streamUri() ?: received.clipData?.let { clip ->
                if (clip.itemCount > 0) clip.getItemAt(0).uri else null
            }
            else -> null
        } ?: return null
        val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: return null
        return mapOf("bytes" to bytes, "name" to queryDisplayName(uri))
    }

    private fun Intent.streamUri(): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun queryDisplayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
            }

    /// Inserts into the Downloads collection (MediaStore) and writes the
    /// bytes. On API 29+ this requires no permission at all; MediaStore
    /// uniquifies the display name on collision.
    private fun saveToDownloads(bytes: ByteArray, fileName: String): String {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, "image/svg+xml")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("MediaStore rejected the insert")
        contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
            ?: throw IOException("could not open the output stream")
        return queryDisplayName(uri) ?: fileName
    }

    private companion object {
        const val CHANNEL = "vtracer_android/platform"
    }
}
