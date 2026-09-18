package com.arunesh.anvil

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.print.PdfPrintBridge
import android.print.PrintAttributes
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Handles the `anvil/pdf` platform channel. Currently one op:
 * `fromUrl {url, outPath}` — loads the URL in an offscreen WebView and prints
 * it to a PDF file via the WebView print pipeline. WebView requires the main
 * thread; the print adapter itself writes on a system worker.
 */
object PdfChannel {
    const val NAME = "anvil/pdf"

    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "fromUrl" -> {
                    val url = call.argument<String>("url")
                    val outPath = call.argument<String>("outPath")
                    if (url.isNullOrBlank() || outPath.isNullOrBlank()) {
                        result.error("pdf_op", "A page URL is required.", null)
                    } else {
                        mainHandler.post { fromUrl(context, url, outPath, result) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun fromUrl(
        context: Context,
        url: String,
        outPath: String,
        result: MethodChannel.Result,
    ) {
        val webView = WebView(context)
        webView.settings.javaScriptEnabled = true
        webView.settings.loadWithOverviewMode = true
        webView.settings.useWideViewPort = true
        // A4-ish virtual screen so responsive pages lay out for print width.
        webView.layout(0, 0, 1080, 1527)

        var finished = false
        val fail = { msg: String ->
            if (!finished) {
                finished = true
                webView.destroy()
                result.error("pdf_op", msg, null)
            }
        }

        // Hard timeout: pages that never fire onPageFinished must not hang the tool.
        mainHandler.postDelayed({ fail("The page took too long to load.") }, 45_000)

        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, loadedUrl: String) {
                if (finished) return
                // Give late JS/webfonts a moment before printing.
                mainHandler.postDelayed({ printToPdf(view, outPath, result) { finished = true } }, 1_500)
            }
        }
        webView.loadUrl(url)
    }

    private fun printToPdf(
        webView: WebView,
        outPath: String,
        result: MethodChannel.Result,
        markFinished: () -> Unit,
    ) {
        try {
            val adapter = webView.createPrintDocumentAdapter("anvil-webpage")
            val attributes = PrintAttributes.Builder()
                .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                .setResolution(PrintAttributes.Resolution("pdf", "pdf", 300, 300))
                .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                .build()
            val file = File(outPath)
            file.parentFile?.mkdirs()
            val fd = ParcelFileDescriptor.open(
                file,
                ParcelFileDescriptor.MODE_CREATE or
                    ParcelFileDescriptor.MODE_TRUNCATE or
                    ParcelFileDescriptor.MODE_READ_WRITE,
            )
            PdfPrintBridge.writeTo(adapter, attributes, fd) { error ->
                mainHandler.post {
                    markFinished()
                    fd.close()
                    webView.destroy()
                    if (error == null) {
                        result.success(null)
                    } else {
                        result.error("pdf_op", error, null)
                    }
                }
            }
        } catch (e: Throwable) {
            markFinished()
            webView.destroy()
            result.error("pdf_op", "Could not render the page: ${e.message}", null)
        }
    }
}
