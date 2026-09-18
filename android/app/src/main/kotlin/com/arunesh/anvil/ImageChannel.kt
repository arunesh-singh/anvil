package com.arunesh.anvil

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Handles the `anvil/image` platform channel: deterministic Android Bitmap ops
 * (resize/crop/compress/flip/grayscale/border/pixelate/format-convert/EXIF).
 * Every op runs on a background executor; results post back on the main thread.
 *
 * Cross-agent contract: op `convert` with args `{format: png|jpg|webp, quality}`
 * decodes ANY Android-supported input (incl. HEIC on API 28+) and re-encodes.
 */
object ImageChannel {
    const val NAME = "anvil/image"

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** User-presentable op failure; message is shown verbatim in the app. */
    private class ImageOpException(message: String) : Exception(message)

    private fun fail(msg: String): Nothing = throw ImageOpException(msg)

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    val out = dispatch(call)
                    mainHandler.post { result.success(out) }
                } catch (e: ImageOpException) {
                    mainHandler.post { result.error("image_op", e.message, null) }
                } catch (e: Throwable) {
                    val detail = e.message ?: e.javaClass.simpleName
                    mainHandler.post {
                        result.error("image_op", "Image processing failed: $detail", null)
                    }
                }
            }
        }
    }

    // ── Dispatch ─────────────────────────────────────────────────────────────

    private fun dispatch(call: MethodCall): Any = when (call.method) {
        "convert" -> encode(decode(call.src()), call.str("format"), call.int("quality", 90))
        "resize" -> resize(call)
        "crop" -> crop(call)
        "cropCircle" -> cropCircle(decode(call.src()))
        "flip" -> flip(call)
        "grayscale" -> encodeAs(call, grayscale(decode(call.src())))
        "border" -> border(call)
        "pixelate" -> pixelate(call)
        "compress" -> encode(decode(call.src()), call.str("format", "jpg"), call.int("quality", 75))
        "composite" -> composite(call)
        "grid" -> grid(call)
        "split" -> split(call)
        "metadataRead" -> metadataRead(call.src())
        "metadataStrip" -> encodeAs(call, decode(call.src()))
        else -> fail("Unknown image operation '${call.method}'.")
    }

    // ── Argument helpers ─────────────────────────────────────────────────────

    private fun MethodCall.src(): ByteArray =
        argument<ByteArray>("src") ?: fail("No image data was provided.")

    private fun MethodCall.int(key: String, default: Int? = null): Int =
        argument<Number>(key)?.toInt()
            ?: default
            ?: fail("Missing required option '$key'.")

    private fun MethodCall.str(key: String, default: String? = null): String =
        argument<String>(key)
            ?: default
            ?: fail("Missing required option '$key'.")

    // ── Codec ────────────────────────────────────────────────────────────────

    private fun decode(bytes: ByteArray): Bitmap {
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { return it }
        if (isHeif(bytes) && Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            fail("HEIC/HEIF images need Android 9 or newer on this device.")
        }
        fail("Could not read the image — the file may be corrupted or in an unsupported format.")
    }

    /** ISO-BMFF `ftyp` sniff for the HEIF/HEIC brand family. */
    private fun isHeif(b: ByteArray): Boolean {
        if (b.size < 12) return false
        if (String(b, 4, 4, Charsets.US_ASCII) != "ftyp") return false
        val brand = String(b, 8, 4, Charsets.US_ASCII)
        return brand.startsWith("hei") || brand.startsWith("hev") ||
            brand == "mif1" || brand == "msf1"
    }

    private fun encode(bmp: Bitmap, format: String, quality: Int): ByteArray {
        val q = quality.coerceIn(0, 100)
        val out = ByteArrayOutputStream()
        val ok = when (format.lowercase()) {
            "png" -> bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
            "jpg", "jpeg" -> opaque(bmp).compress(Bitmap.CompressFormat.JPEG, q, out)
            "webp" ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    bmp.compress(Bitmap.CompressFormat.WEBP_LOSSY, q, out)
                } else {
                    @Suppress("DEPRECATION")
                    bmp.compress(Bitmap.CompressFormat.WEBP, q, out)
                }
            else -> fail("Unsupported output format '$format' — use png, jpg, or webp.")
        }
        if (!ok || out.size() == 0) fail("Could not encode the image as $format.")
        return out.toByteArray()
    }

    /** Encodes with the call's `format`/`quality` args (transform ops keep input format). */
    private fun encodeAs(call: MethodCall, bmp: Bitmap): ByteArray =
        encode(bmp, call.str("format", "png"), call.int("quality", 90))

    /** JPEG has no alpha channel; composite transparent bitmaps onto white first. */
    private fun opaque(bmp: Bitmap): Bitmap {
        if (!bmp.hasAlpha()) return bmp
        val out = Bitmap.createBitmap(bmp.width, bmp.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(bmp, 0f, 0f, null)
        return out
    }

    // ── Ops ──────────────────────────────────────────────────────────────────

    private fun resize(call: MethodCall): ByteArray {
        val bmp = decode(call.src())
        var w = call.int("width", 0)
        var h = call.int("height", 0)
        if (w <= 0 && h <= 0) fail("Set a target width or height (0 keeps the aspect ratio).")
        if (w <= 0) w = max(1, (h * bmp.width.toFloat() / bmp.height).roundToInt())
        if (h <= 0) h = max(1, (w * bmp.height.toFloat() / bmp.width).roundToInt())
        return encodeAs(call, Bitmap.createScaledBitmap(bmp, w, h, true))
    }

    private fun crop(call: MethodCall): ByteArray {
        val bmp = decode(call.src())
        val x = call.int("x")
        val y = call.int("y")
        val w = call.int("width")
        val h = call.int("height")
        if (w <= 0 || h <= 0) fail("Crop width and height must be positive.")
        if (x < 0 || y < 0 || x + w > bmp.width || y + h > bmp.height) {
            fail("Crop rectangle is outside the image bounds (image is ${bmp.width}×${bmp.height}).")
        }
        return encodeAs(call, Bitmap.createBitmap(bmp, x, y, w, h))
    }

    /** Center-crops to the largest circle; always returns a transparent PNG. */
    private fun cropCircle(bmp: Bitmap): ByteArray {
        val d = min(bmp.width, bmp.height)
        val out = Bitmap.createBitmap(d, d, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.drawCircle(d / 2f, d / 2f, d / 2f, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(bmp, (d - bmp.width) / 2f, (d - bmp.height) / 2f, paint)
        return encode(out, "png", 100)
    }

    private fun flip(call: MethodCall): ByteArray {
        val bmp = decode(call.src())
        val horizontal = call.int("horizontal", 1) != 0
        val m = Matrix()
        if (horizontal) m.preScale(-1f, 1f) else m.preScale(1f, -1f)
        return encodeAs(call, Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true))
    }

    private fun grayscale(bmp: Bitmap): Bitmap {
        val out = Bitmap.createBitmap(bmp.width, bmp.height, Bitmap.Config.ARGB_8888)
        val paint = Paint().apply {
            colorFilter = ColorMatrixColorFilter(ColorMatrix().apply { setSaturation(0f) })
        }
        Canvas(out).drawBitmap(bmp, 0f, 0f, paint)
        return out
    }

    private fun border(call: MethodCall): ByteArray {
        val bmp = decode(call.src())
        val size = call.int("sizePx")
        if (size <= 0) fail("Border size must be at least 1 pixel.")
        val colorStr = call.str("color", "#FF000000")
        val color = try {
            Color.parseColor(if (colorStr.startsWith("#")) colorStr else "#$colorStr")
        } catch (_: IllegalArgumentException) {
            fail("Invalid color '$colorStr' — use hex like #FF0000 or #80FF0000.")
        }
        val out = Bitmap.createBitmap(
            bmp.width + 2 * size, bmp.height + 2 * size, Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(out)
        canvas.drawColor(color)
        canvas.drawBitmap(bmp, size.toFloat(), size.toFloat(), null)
        return encodeAs(call, out)
    }

    private fun pixelate(call: MethodCall): ByteArray {
        val bmp = decode(call.src())
        val block = call.int("blockSize")
        if (block < 1) fail("Pixel block size must be at least 1.")
        val small = Bitmap.createScaledBitmap(
            bmp, max(1, bmp.width / block), max(1, bmp.height / block), true,
        )
        return encodeAs(call, Bitmap.createScaledBitmap(small, bmp.width, bmp.height, false))
    }

    private fun composite(call: MethodCall): ByteArray {
        val base = decode(call.src())
        val out = base.copy(Bitmap.Config.ARGB_8888, true)
            ?: fail("Could not prepare the base image.")
        val canvas = Canvas(out)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        val layers = call.argument<List<Map<String, Any?>>>("layers")
            ?: fail("No overlay layers were provided.")
        for (layer in layers) {
            val bytes = layer["overlay"] as? ByteArray ?: continue
            val top = decode(bytes)
            val x = (layer["x"] as? Number)?.toFloat() ?: 0f
            val y = (layer["y"] as? Number)?.toFloat() ?: 0f
            val lw = (layer["width"] as? Number)?.toInt() ?: 0
            val lh = (layer["height"] as? Number)?.toInt() ?: 0
            val w = if (lw > 0) lw else top.width
            val h = if (lh > 0) lh else top.height
            val rot = (layer["rotation"] as? Number)?.toFloat() ?: 0f
            val m = Matrix()
            m.postScale(w.toFloat() / top.width, h.toFloat() / top.height)
            m.postTranslate(x, y)
            if (rot != 0f) m.postRotate(rot, x + w / 2f, y + h / 2f)
            canvas.drawBitmap(top, m, paint)
        }
        return encodeAs(call, out)
    }

    /** Lays every input image out on a fit-center grid; transparent PNG output. */
    private fun grid(call: MethodCall): ByteArray {
        val images = call.argument<List<ByteArray>>("images")
        if (images.isNullOrEmpty()) fail("No images were provided.")
        val bmps = images.map { decode(it) }
        val cols = call.int("columns", 0).let { if (it <= 0) bmps.size else min(it, bmps.size) }
        val rows = (bmps.size + cols - 1) / cols
        val cellW = bmps.maxOf { it.width }
        val cellH = bmps.maxOf { it.height }
        if (cellW.toLong() * cols * cellH * rows > 100_000_000L) {
            fail("The combined image would be too large — use smaller images or fewer of them.")
        }
        val out = Bitmap.createBitmap(cellW * cols, cellH * rows, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        bmps.forEachIndexed { i, bmp ->
            val scale = min(cellW.toFloat() / bmp.width, cellH.toFloat() / bmp.height)
            val w = bmp.width * scale
            val h = bmp.height * scale
            val left = (i % cols) * cellW + (cellW - w) / 2f
            val top = (i / cols) * cellH + (cellH - h) / 2f
            canvas.drawBitmap(bmp, null, RectF(left, top, left + w, top + h), paint)
        }
        return encode(out, "png", 100)
    }

    /** Cuts the image into a rows×cols grid; returns PNG tiles in row-major order. */
    private fun split(call: MethodCall): ArrayList<ByteArray> {
        val bmp = decode(call.src())
        val rows = call.int("rows")
        val cols = call.int("cols")
        if (rows < 1 || cols < 1) fail("Rows and columns must be at least 1.")
        if (cols > bmp.width || rows > bmp.height) {
            fail("Cannot split a ${bmp.width}×${bmp.height} image into $rows×$cols tiles.")
        }
        val tileW = bmp.width / cols
        val tileH = bmp.height / rows
        val out = ArrayList<ByteArray>(rows * cols)
        for (r in 0 until rows) {
            for (c in 0 until cols) {
                // Last row/column absorbs the integer-division remainder.
                val w = if (c == cols - 1) bmp.width - c * tileW else tileW
                val h = if (r == rows - 1) bmp.height - r * tileH else tileH
                out.add(encode(Bitmap.createBitmap(bmp, c * tileW, r * tileH, w, h), "png", 100))
            }
        }
        return out
    }

    /** Common EXIF tag names understood by [android.media.ExifInterface.getAttribute]. */
    private val exifTags = listOf(
        "Make", "Model", "Software", "Artist", "Copyright",
        "DateTime", "DateTimeOriginal", "DateTimeDigitized",
        "ExposureTime", "FNumber", "FocalLength", "ISOSpeedRatings",
        "Flash", "WhiteBalance", "Orientation", "ImageWidth", "ImageLength",
        "GPSLatitude", "GPSLatitudeRef", "GPSLongitude", "GPSLongitudeRef",
        "GPSAltitude", "GPSDateStamp",
    )

    @Suppress("DEPRECATION") // framework ExifInterface avoids an androidx dependency.
    private fun metadataRead(bytes: ByteArray): HashMap<String, Any> {
        val map = HashMap<String, Any>()
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth > 0) map["Width"] = bounds.outWidth
        if (bounds.outHeight > 0) map["Height"] = bounds.outHeight
        try {
            val exif = android.media.ExifInterface(ByteArrayInputStream(bytes))
            for (tag in exifTags) {
                exif.getAttribute(tag)?.let { map[tag] = it }
            }
            val latLong = FloatArray(2)
            if (exif.getLatLong(latLong)) {
                map["GPSLatitude"] = latLong[0].toDouble()
                map["GPSLongitude"] = latLong[1].toDouble()
            }
        } catch (_: Exception) {
            // Not an EXIF-bearing format (e.g. plain PNG) — dimensions alone are fine.
        }
        if (map.isEmpty()) {
            fail("Could not read the image — the file may be corrupted or in an unsupported format.")
        }
        return map
    }
}
