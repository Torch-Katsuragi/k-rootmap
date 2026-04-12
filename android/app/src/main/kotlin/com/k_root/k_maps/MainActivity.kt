package com.k_root.k_maps

import android.app.NotificationChannel
import android.app.NotificationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.k_root.k_maps/media_copy"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Android 8.0以降で通知チャンネルを作成
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "k_maps_foreground_channel"
            val channelName = "RootMap GIS フォアグラウンドサービス"
            val channelDescription = "RootMap GISアプリのフォアグラウンドサービス通知"
            val importance = NotificationManager.IMPORTANCE_LOW
            
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
                setShowBadge(false) // バッジ表示を無効化
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copyOriginal" -> {
                        val uriStr = call.argument<String>("uri")
                        val destPath = call.argument<String>("destPath")
                        if (uriStr == null || destPath == null) {
                            result.error("INVALID_ARGS", "uri and destPath are required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val success = copyOriginalFile(uriStr, destPath)
                            result.success(success)
                        } catch (e: Exception) {
                            result.error("COPY_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * content URI から元ファイルをバイトコピーする。
     *
     * 1. MediaStore で実パスを解決 → MANAGE_EXTERNAL_STORAGE で直接コピー（EXIF完全保持）
     * 2. 実パスが取れない場合は ContentResolver の InputStream からバイトコピー（フォールバック）
     */
    private fun copyOriginalFile(uriStr: String, destPath: String): Boolean {
        val uri = Uri.parse(uriStr)
        val dest = File(destPath)

        // 方法1: MediaStore から実ファイルパスを取得して直接コピー
        val realPath = resolveRealPath(uri)
        if (realPath != null) {
            val src = File(realPath)
            if (src.exists() && src.canRead()) {
                src.copyTo(dest, overwrite = true)
                return true
            }
        }

        // 方法2: ContentResolver の InputStream からバイトコピー（フォールバック）
        contentResolver.openInputStream(uri)?.use { input ->
            dest.outputStream().use { output ->
                input.copyTo(output)
            }
            return true
        }

        return false
    }

    /**
     * content:// URI から実ファイルシステムのパスを解決する。
     * MANAGE_EXTERNAL_STORAGE 権限があるため _data カラムの実パスに直接アクセスできる。
     */
    private fun resolveRealPath(uri: Uri): String? {
        if (uri.scheme == "file") return uri.path

        return try {
            val projection = arrayOf(MediaStore.Images.Media.DATA)
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                    if (idx >= 0) cursor.getString(idx) else null
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }
}
