package tw.com.tutorarthur.allmodiary

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.Metadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.container.Mp4OrientationData
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import androidx.media3.muxer.BufferInfo
import androidx.media3.muxer.Muxer
import androidx.media3.transformer.AudioEncoderSettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMp4Muxer
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.google.common.collect.ImmutableList
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * Diary videos: picking one from the photo library, reading single frames, and storing a shrunk
 * (and trimmed) copy.
 *
 * - Picking uses the system photo picker, which hands over one video without any permission to
 *   read the library. The video is read where it is (a content URI); nothing is copied first, so a
 *   long 4K recording needs no free space of its own size.
 * - Shrinking uses Jetpack Media3 Transformer (the phone's hardware codecs): H.264 video and AAC
 *   sound in an MP4 file.
 * - The stored file keeps nothing the original said about itself (where and when it was filmed,
 *   the camera): see [PrivateMuxer].
 */
@OptIn(UnstableApi::class)
class VideoChannel(private val activity: Activity) {
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())

    /** Reading frames and metadata can take a while on a 4K file; never on the main thread. */
    private val background = Executors.newSingleThreadExecutor()

    private var pendingPick: MethodChannel.Result? = null
    private var job: Job? = null

    private class Job(val out: File, val result: MethodChannel.Result) {
        lateinit var transformer: Transformer
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "tw.com.tutorarthur.allmodiary/video")
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "pick" -> pick(result)
                    "describe" -> describe(call, result)
                    "frame" -> frame(call, result)
                    "transcode" -> transcode(call, result)
                    "cancel" -> {
                        cancel()
                        result.success(null)
                    }
                    "keepScreenOn" -> {
                        keepAwake("playing", call.argument<Boolean>("on") == true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("video_failed", e.javaClass.simpleName, null)
            }
        }
    }

    // ── Picking ─────────────────────────────────────────────────

    private fun pick(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "the picker is already open", null)
            return
        }
        // The contract only builds the intent here (the activity is a FlutterActivity, which has no
        // activity-result registry). It picks the system photo picker, or the fallbacks it knows on
        // phones without one.
        val intent = ActivityResultContracts.PickVisualMedia().createIntent(
            activity,
            PickVisualMediaRequest.Builder().setMediaType(ActivityResultContracts.PickVisualMedia.VideoOnly).build(),
        )
        pendingPick = result
        try {
            activity.startActivityForResult(intent, PICK_REQUEST)
        } catch (e: ActivityNotFoundException) {
            pendingPick = null
            result.error("no_picker", "no app on this phone can pick a video", null)
        }
    }

    /** Called by the activity. true when the result was the video picker's. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = ActivityResultContracts.PickVisualMedia().parseResult(resultCode, data)
        if (uri == null) {
            result.success(null)
            return true
        }
        background.execute {
            try {
                val info = describe(uri)
                main.post { result.success(info) }
            } catch (e: Throwable) {
                main.post { result.error("unreadable", e.javaClass.simpleName, null) }
            }
        }
        return true
    }

    /** What the phone reads about the video at `source` (see the other [describe]). */
    private fun describe(call: MethodCall, result: MethodChannel.Result) {
        val source = Uri.parse(call.argument<String>("source")!!)
        background.execute {
            try {
                val info = describe(source)
                main.post { result.success(info) }
            } catch (e: Throwable) {
                main.post { result.error("unreadable", e.javaClass.simpleName, null) }
            }
        }
    }

    /**
     * Length and size as shown (upright), and what else the file says about itself: how many
     * frames, whether it has sound, where it was filmed. Throws when the file has no video the
     * phone can read.
     */
    private fun describe(uri: Uri): Map<String, Any?> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(activity, uri)
            fun number(key: Int) = retriever.extractMetadata(key)?.toLongOrNull() ?: 0L
            val durationMs = number(MediaMetadataRetriever.METADATA_KEY_DURATION)
            var width = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH).toInt()
            var height = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT).toInt()
            val rotation = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION).toInt()
            if (rotation == 90 || rotation == 270) width = height.also { height = width }
            require(durationMs > 0 && width > 0 && height > 0) { "not a video" }
            return mapOf(
                "uri" to uri.toString(),
                "durationMs" to durationMs,
                "width" to width,
                "height" to height,
                "frames" to number(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT),
                "hasAudio" to (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"),
                "location" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_LOCATION),
            )
        } finally {
            retriever.release()
        }
    }

    // ── Frames ──────────────────────────────────────────────────

    /**
     * One frame as a JPEG with its pixel size, upright. `source` is a content or file URI, `timeMs`
     * the position (the nearest key frame is used: quick, and exact at 0), `maxHeight` (optional)
     * shrinks it.
     */
    private fun frame(call: MethodCall, result: MethodChannel.Result) {
        val source = Uri.parse(call.argument<String>("source")!!)
        val timeUs = (call.argument<Number>("timeMs")?.toLong() ?: 0L) * 1000
        val maxHeight = call.argument<Int>("maxHeight")
        val quality = call.argument<Int>("quality") ?: 85
        background.execute {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(activity, source)
                val option = MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                // The scaled call fits the frame inside the box keeping its shape; the width is
                // left wide open so only the height limits it.
                val bitmap: Bitmap? = if (maxHeight != null) {
                    retriever.getScaledFrameAtTime(timeUs, option, maxHeight * 8, maxHeight)
                } else {
                    retriever.getFrameAtTime(timeUs, option)
                }
                if (bitmap == null) {
                    main.post { result.error("no_frame", "no frame at that position", null) }
                    return@execute
                }
                val bytes = ByteArrayOutputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it)
                    it.toByteArray()
                }
                val answer = mapOf("bytes" to bytes, "width" to bitmap.width, "height" to bitmap.height)
                bitmap.recycle()
                main.post { result.success(answer) }
            } catch (e: Throwable) {
                main.post { result.error("no_frame", e.javaClass.simpleName, null) }
            } finally {
                retriever.release()
            }
        }
    }

    // ── Shrinking ───────────────────────────────────────────────

    /**
     * Writes a shrunk copy of `source` to `out`: the part between `startMs` and `endMs` (both
     * optional), `height` pixels tall as shown (width by its shape), at `bitrate`, with frames above
     * `maxFrameRate` dropped. Answers when done; progress (0–100) is sent as "progress" meanwhile.
     * One at a time.
     */
    private fun transcode(call: MethodCall, result: MethodChannel.Result) {
        if (job != null) {
            result.error("busy", "another video is being processed", null)
            return
        }
        val request = Request(
            source = Uri.parse(call.argument<String>("source")!!),
            out = File(call.argument<String>("out")!!),
            startMs = call.argument<Number>("startMs")?.toLong(),
            endMs = call.argument<Number>("endMs")?.toLong(),
            height = call.argument<Int>("height")!!,
            bitrate = call.argument<Int>("bitrate")!!,
            audioBitrate = call.argument<Int>("audioBitrate")!!,
            maxFrameRate = call.argument<Int>("maxFrameRate")!!,
        )
        start(request, result, HDR_MODES.first())
    }

    private class Request(
        val source: Uri,
        val out: File,
        val startMs: Long?,
        val endMs: Long?,
        val height: Int,
        val bitrate: Int,
        val audioBitrate: Int,
        val maxFrameRate: Int,
    )

    /** One attempt at [request], turning HDR into ordinary video the way [hdrMode] says. */
    private fun start(request: Request, result: MethodChannel.Result, hdrMode: Int) {
        val source = request.source
        val out = request.out
        val startMs = request.startMs
        val endMs = request.endMs
        val height = request.height
        val bitrate = request.bitrate
        val audioBitrate = request.audioBitrate
        val maxFrameRate = request.maxFrameRate

        val item = MediaItem.Builder().setUri(source)
        if (startMs != null || endMs != null) {
            val clip = MediaItem.ClippingConfiguration.Builder()
            if (startMs != null) clip.setStartPositionMs(startMs)
            if (endMs != null) clip.setEndPositionMs(endMs)
            item.setClippingConfiguration(clip.build())
        }
        val edited = EditedMediaItem.Builder(item.build())
            .setEffects(
                Effects(
                    emptyList(),
                    listOf(
                        FrameDropEffect.createDefaultFrameDropEffect(maxFrameRate.toFloat()),
                        // Encoders need even sides.
                        Presentation.createForHeight(height).copyWithUnsetSideRoundedTo(2),
                    ),
                ),
            )
            .build()
        // HDR recordings are stored as ordinary (SDR) video: H.264 as written here has no HDR.
        val composition = Composition.Builder(EditedMediaItemSequence.Builder(edited).build())
            .setHdrMode(hdrMode)
            .build()
        val context = activity.applicationContext
        // Callbacks name the job they belong to: one arriving late, after its job was cancelled and
        // another started, must not end the other.
        val mine = Job(out, result)
        mine.transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(
                DefaultEncoderFactory.Builder(context)
                    .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build())
                    .setRequestedAudioEncoderSettings(AudioEncoderSettings.Builder().setBitrate(audioBitrate).build())
                    .build(),
            )
            // The index of the file goes at its end. Asking for it at the start ("streamable")
            // makes the muxer set aside 400 kB for it in every file, most of it never used; a diary
            // video is always played from a complete file, so there is nothing to gain from it.
            .setMuxerFactory(PrivateMuxer.Factory(InAppMp4Muxer.Factory().setAttemptStreamableOutputEnabled(false)))
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    val durationMs =
                        if (exportResult.durationMs > 0) exportResult.durationMs else exportResult.approximateDurationMs
                    finish(mine) { it.success(mapOf("durationMs" to durationMs, "bytes" to out.length())) }
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    if (job !== mine) return
                    out.delete()
                    // Turning HDR into ordinary video needs things not every phone has (OpenGL
                    // extensions, a decoder that can do it). On a failure of that step, try the next
                    // way; the last one keeps the picture as it is, which only looks paler.
                    val next = HDR_MODES.getOrNull(HDR_MODES.indexOf(hdrMode) + 1)
                    val hdrStep = exportException.errorCode == ExportException.ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED ||
                        exportException.errorCode == ExportException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED ||
                        exportException.errorCode == ExportException.ERROR_CODE_DECODER_INIT_FAILED
                    if (next != null && hdrStep) {
                        job = null
                        main.removeCallbacks(progress)
                        Log.w(TAG, "video: ${exportException.errorCodeName} with HDR mode $hdrMode, trying $next")
                        start(request, result, next)
                        return
                    }
                    finish(mine) { it.error("failed", exportException.errorCodeName, null) }
                }
            })
            .build()
        out.parentFile?.mkdirs()
        out.delete()
        job = mine
        // The screen stays on while working: with the screen off the phone may stop the app.
        keepAwake("working", true)
        try {
            mine.transformer.start(composition, out.absolutePath)
        } catch (e: Throwable) {
            out.delete()
            finish(mine) { it.error("failed", e.javaClass.simpleName, null) }
            return
        }
        main.postDelayed(progress, PROGRESS_INTERVAL_MS)
    }

    private val progressHolder = ProgressHolder()
    private val progress = object : Runnable {
        override fun run() {
            val current = job ?: return
            if (current.transformer.getProgress(progressHolder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                channel.invokeMethod("progress", progressHolder.progress)
            }
            main.postDelayed(this, PROGRESS_INTERVAL_MS)
        }
    }

    /** Ends [which] and answers its caller. Nothing happens when it is no longer the current job. */
    private fun finish(which: Job, answer: (MethodChannel.Result) -> Unit) {
        if (job !== which) return
        job = null
        main.removeCallbacks(progress)
        keepAwake("working", false)
        answer(which.result)
    }

    // ── Screen ──────────────────────────────────────────────────

    private val awake = mutableSetOf<String>()

    /** The screen stays on while anything asks for it (shrinking a video, playing one). */
    private fun keepAwake(reason: String, on: Boolean) {
        if (on) awake.add(reason) else awake.remove(reason)
        if (awake.isEmpty()) {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun cancel() {
        val current = job ?: return
        current.transformer.cancel()
        current.out.delete()
        finish(current) { it.error("cancelled", "cancelled", null) }
    }

    /** The activity is going away: stop working and drop what is half-written. */
    fun dispose() {
        cancel()
        keepAwake("playing", false)
        pendingPick = null
        background.shutdown()
    }

    companion object {
        private const val PICK_REQUEST = 0x5649
        private const val TAG = "AllMoDiary"

        /** Ways to turn HDR into ordinary video, best first. Ordinary video passes all of them unchanged. */
        private val HDR_MODES = listOf(
            Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL,
            Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_MEDIACODEC,
            Composition.HDR_MODE_EXPERIMENTAL_FORCE_INTERPRET_HDR_AS_SDR,
        )
        private const val PROGRESS_INTERVAL_MS = 300L
    }
}

/**
 * Writes the file with [inner], passing on nothing the source file said about itself except how
 * the picture is turned. A phone's camera writes where a video was filmed (and when, and with
 * what) into the file; a diary video keeps none of it, like diary images, which lose their EXIF.
 */
@OptIn(UnstableApi::class)
private class PrivateMuxer(private val inner: Muxer) : Muxer {
    override fun addTrack(format: Format): Int = inner.addTrack(format)

    override fun writeSampleData(trackId: Int, byteBuffer: ByteBuffer, bufferInfo: BufferInfo) =
        inner.writeSampleData(trackId, byteBuffer, bufferInfo)

    override fun addMetadataEntry(metadataEntry: Metadata.Entry) {
        if (metadataEntry is Mp4OrientationData) inner.addMetadataEntry(metadataEntry)
    }

    override fun close() = inner.close()

    class Factory(private val inner: Muxer.Factory) : Muxer.Factory {
        override fun create(path: String): Muxer = PrivateMuxer(inner.create(path))

        override fun getSupportedSampleMimeTypes(trackType: Int): ImmutableList<String> =
            inner.getSupportedSampleMimeTypes(trackType)

        override fun supportsWritingNegativeTimestampsInEditList(): Boolean =
            inner.supportsWritingNegativeTimestampsInEditList()
    }
}
