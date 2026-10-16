package com.arunesh.anvil

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Handles the `anvil/clipboard` platform channel: `readMedia {mimePrefix}`.
 *
 * Flutter's Clipboard API is text-only, so the tool picker's Paste button reads
 * a copied image/video here: the first clip item whose content URI resolves to
 * a type starting with `mimePrefix` (e.g. `image/`) is copied into the cache
 * and returned as `{path, name}`; anything else returns null. Android 10+ only
 * lets the focused foreground app read the clipboard, which a button tap is.
 */
object ClipboardChannel {
    const val NAME = "anvil/clipboard"

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "readMedia" -> {
                    val prefix = call.argument<String>("mimePrefix") ?: "image/"
                    val clip = (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                        .primaryClip
                    // Resolve the URI on the main thread (clip access), copy off it.
                    val uri = clip?.let { c ->
                        (0 until c.itemCount).asSequence()
                            .mapNotNull { c.getItemAt(it).uri }
                            .firstOrNull { (context.contentResolver.getType(it) ?: "").startsWith(prefix) }
                    }
                    if (uri == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        try {
                            val out = copyToCache(context, uri)
                            mainHandler.post { result.success(out) }
                        } catch (e: Throwable) {
                            mainHandler.post {
                                result.error("clipboard", "Could not read the copied item: ${e.message}", null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun copyToCache(context: Context, uri: Uri): Map<String, String> {
        val resolver = context.contentResolver
        val type = resolver.getType(uri) ?: ""
        val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(type) ?: "bin"
        val display = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        val name = display?.takeIf { it.contains('.') } ?: "pasted_${System.currentTimeMillis()}.$ext"
        val dir = File(context.cacheDir, "pasted").apply { mkdirs() }
        val file = File(dir, "${System.currentTimeMillis()}_$name")
        resolver.openInputStream(uri)?.use { input ->
            file.outputStream().use { input.copyTo(it) }
        } ?: throw IllegalStateException("no data")
        return mapOf("path" to file.absolutePath, "name" to name)
    }
}
