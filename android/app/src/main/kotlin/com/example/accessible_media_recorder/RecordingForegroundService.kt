package com.example.accessible_media_recorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * سرویس پیش‌زمینه‌ای بسیار ساده. این سرویس هیچ ضبطی خودش انجام نمی‌دهد،
 * فقط با نمایش یک اعلان ثابت باعث می‌شود سیستم عامل برنامه را در حالت
 * صفحه خاموش یا پس‌زمینه نبندد تا ضبط صدا که در همان برنامه در حال اجراست ادامه یابد.
 */
class RecordingForegroundService : Service() {

    private val channelId = "acc_rec_recording_channel"
    private val notificationId = 1001

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannelIfNeeded()
        val notification = buildNotification()
        startForeground(notificationId, notification)
        return START_STICKY
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val existing = manager.getNotificationChannel(channelId)
            if (existing == null) {
                val channel = NotificationChannel(
                    channelId,
                    "ضبط در حال انجام",
                    NotificationManager.IMPORTANCE_LOW
                )
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("ضبط رسانه دسترس‌پذیر")
            .setContentText("در حال ضبط است")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
