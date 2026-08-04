package coach.interview.dau_app_badge

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DauAppBadgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val BADGE_CHANNEL = "coach.interview.daufootytipping/app_badge"
        private const val BADGE_NOTIFICATION_CHANNEL_ID = "outstanding_tips"
        private const val REMINDER_NOTIFICATION_CHANNEL_ID = "tipping_reminders_v1"
        private const val NOTIFICATION_ID = 6761
    }

    private lateinit var context: Context
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        createNotificationChannels()
        channel = MethodChannel(binding.binaryMessenger, BADGE_CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "setCount") {
            result.notImplemented()
            return
        }

        val count = call.argument<Int>("count")
        if (count == null || count < 0) {
            result.error("invalid_count", "Badge count must not be negative", null)
            return
        }
        result.success(setOutstandingTipsCount(count))
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val notificationManager = context.getSystemService(NotificationManager::class.java)
        val badgeChannel = NotificationChannel(
            BADGE_NOTIFICATION_CHANNEL_ID,
            "Outstanding tips",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows how many tips still need to be submitted"
            setShowBadge(true)
        }
        val reminderChannel = NotificationChannel(
            REMINDER_NOTIFICATION_CHANNEL_ID,
            "Tipping reminders",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Alerts when tipping for a game is closing soon"
            setShowBadge(false)
        }
        notificationManager.createNotificationChannels(
            listOf(badgeChannel, reminderChannel),
        )
    }

    private fun setOutstandingTipsCount(count: Int): Boolean {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (count == 0) {
            notificationManager.cancel(NOTIFICATION_ID)
            return true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val text = if (count == 1) "1 tip outstanding" else "$count tips outstanding"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, BADGE_NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
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
