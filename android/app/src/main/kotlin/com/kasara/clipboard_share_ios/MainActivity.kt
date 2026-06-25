package com.kasara.clipboard_share_ios

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

        MethodChannel(messenger, "clipsync/pasteboard").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasStrings" -> result.success(hasText(clipboard))
                "hasImages" -> result.success(hasImage(clipboard))
                "getText" -> result.success(getText(clipboard))
                "getImage" -> result.success(getImagePng(clipboard))
                "setText" -> {
                    val text = call.arguments as? String
                    if (text == null) {
                        result.error("bad_args", "setText expects String", null)
                    } else {
                        clipboard.setPrimaryClip(ClipData.newPlainText("ClipSync", text))
                        result.success(null)
                    }
                }
                "setImage" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null) {
                        result.error("bad_args", "setImage expects bytes", null)
                    } else {
                        try {
                            setImagePng(clipboard, bytes)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("set_image_failed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "clipsync/network").setMethodCallHandler { call, result ->
            if (call.method == "prepareAccess") {
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        EventChannel(messenger, "clipsync/clipboard_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    val listener = ClipboardManager.OnPrimaryClipChangedListener {
                        events?.success(null)
                    }
                    clipboardListener = listener
                    clipboard.addPrimaryClipChangedListener(listener)
                }

                override fun onCancel(arguments: Any?) {
                    clipboardListener?.let { clipboard.removePrimaryClipChangedListener(it) }
                    clipboardListener = null
                }
            },
        )
    }

    private fun hasText(clipboard: ClipboardManager): Boolean {
        val clip = clipboard.primaryClip ?: return false
        for (i in 0 until clip.itemCount) {
            val text = clip.getItemAt(i).coerceToText(this)
            if (!text.isNullOrBlank()) return true
        }
        return false
    }

    private fun hasImage(clipboard: ClipboardManager): Boolean {
        return getImageBitmap(clipboard) != null
    }

    private fun getText(clipboard: ClipboardManager): String? {
        val clip = clipboard.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        return clip.getItemAt(0).coerceToText(this)?.toString()
    }

    private fun getImagePng(clipboard: ClipboardManager): ByteArray? {
        val bitmap = getImageBitmap(clipboard) ?: return null
        val output = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        return output.toByteArray()
    }

    private fun getImageBitmap(clipboard: ClipboardManager): Bitmap? {
        val clip = clipboard.primaryClip ?: return null
        for (i in 0 until clip.itemCount) {
            val item = clip.getItemAt(i)
            item.uri?.let { uri ->
                try {
                    contentResolver.openInputStream(uri)?.use { stream ->
                        BitmapFactory.decodeStream(stream)?.let { return it }
                    }
                } catch (_: Exception) {
                }
            }
            if (item.htmlText != null) {
                // HTML クリップは画像抽出対象外
            }
        }
        return null
    }

    private fun setImagePng(clipboard: ClipboardManager, bytes: ByteArray) {
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: throw IllegalArgumentException("Invalid PNG data")
        val file = File(cacheDir, "clipsync_clip.png")
        file.outputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }
        val uri: Uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )
        val clip = ClipData.newUri(contentResolver, "ClipSync", uri)
        clipboard.setPrimaryClip(clip)
    }
}
