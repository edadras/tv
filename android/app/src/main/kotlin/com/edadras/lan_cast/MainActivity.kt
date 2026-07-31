package com.edadras.lan_cast

import android.Manifest
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The whole native half of the app: a handful of platform facts, the keep-awake
 * flag and storage permission. Each of these would otherwise cost a plugin
 * dependency, and plugins are what drag a Flutter build into version conflicts.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "lancast/native"
    private val legacyStorageRequest = 4501

    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceInfo" -> result.success(deviceInfo())

                    "keepAwake" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }

                    "hasStorageAccess" -> result.success(hasStorageAccess())

                    "requestStorageAccess" -> requestStorageAccess(result)

                    else -> result.notImplemented()
                }
            }
    }

    // --- device facts -------------------------------------------------------

    private fun deviceInfo(): Map<String, Any?> = mapOf(
        "name" to deviceName(),
        "isTelevision" to isTelevision(),
        "sdkInt" to Build.VERSION.SDK_INT,
        // Path to our own installed APK. The phone serves this file at
        // /app.apk so the TV can sideload the very same build straight from
        // the browser page — no cable, no transfer app.
        "apkPath" to apkPath(),
    )

    private fun deviceName(): String {
        val brand = Build.MANUFACTURER.orEmpty().replaceFirstChar { it.uppercase() }
        val model = Build.MODEL.orEmpty()
        return when {
            model.isEmpty() -> brand.ifEmpty { "Android" }
            model.startsWith(brand, ignoreCase = true) -> model
            brand.isEmpty() -> model
            else -> "$brand $model"
        }
    }

    private fun apkPath(): String? = try {
        applicationContext.packageManager
            .getPackageInfo(packageName, 0)
            .applicationInfo
            ?.sourceDir
    } catch (e: PackageManager.NameNotFoundException) {
        null
    }

    // Leanback in the manifest is not enough on boxes that ship a
    // phone-flavoured ROM, so ask the system what it thinks it is as well.
    private fun isTelevision(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
        return packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature("android.hardware.type.television")
    }

    // --- storage ------------------------------------------------------------

    /**
     * Reading the original file (rather than a copy handed over by the system
     * picker) is what keeps casting a multi-gigabyte film instant, so we ask
     * for real filesystem access.
     */
    private fun hasStorageAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun requestStorageAccess(result: MethodChannel.Result) {
        if (hasStorageAccess()) {
            result.success(true)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // "All files access" is a Settings screen, not a dialog: it returns
            // no result, so Dart re-checks when the app comes back to the front.
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                .setData(Uri.parse("package:$packageName"))
            try {
                startActivity(intent)
            } catch (e: android.content.ActivityNotFoundException) {
                // Some TV builds ship no such screen; fall back to the app's
                // own settings page.
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.parse("package:$packageName"))
                )
            }
            result.success(false)
            return
        }

        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
            legacyStorageRequest,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != legacyStorageRequest) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
    }
}
