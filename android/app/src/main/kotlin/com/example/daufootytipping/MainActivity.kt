package coach.interview.daufootytipping

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    companion object {
        private const val BADGE_CHANNEL = "coach.interview.daufootytipping/app_badge"
        private const val NOTIFICATION_CHANNEL_ID = "outstanding_tips"
        private const val NOTIFICATION_ID = 6761
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createOutstandingTipsChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BADGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "setCount") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val count = call.argument<Int>("count")
                if (count == null || count < 0) {
                    result.error("invalid_count", "Badge count must not be negative", null)
                    return@setMethodCallHandler
                }
                result.success(setOutstandingTipsCount(count))
            }
    }

    private fun createOutstandingTipsChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Outstanding tips",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows how many tips still need to be submitted"
            setShowBadge(true)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun setOutstandingTipsCount(count: Int): Boolean {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (count == 0) {
            notificationManager.cancel(NOTIFICATION_ID)
            return true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val text = if (count == 1) "1 tip outstanding" else "$count tips outstanding"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_tips)
            .setContentTitle("DAU Tips")
            .setContentText(text)
            .setNumber(count)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setAutoCancel(false)
            .setContentIntent(pendingIntent)
            .build()
        notificationManager.notify(NOTIFICATION_ID, notification)
        return true
    }
}
