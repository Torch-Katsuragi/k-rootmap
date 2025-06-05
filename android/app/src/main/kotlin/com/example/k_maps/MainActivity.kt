package com.example.k_maps

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Android 8.0以降で通知チャンネルを作成
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "k_maps_foreground_channel"
            val channelName = "K-MAPS フォアグラウンドサービス"
            val channelDescription = "K-MAPSアプリのフォアグラウンドサービス通知"
            val importance = NotificationManager.IMPORTANCE_LOW
            
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
                setShowBadge(false) // バッジ表示を無効化
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }
}
