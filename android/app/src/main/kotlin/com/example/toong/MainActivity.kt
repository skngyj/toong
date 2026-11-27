package com.example.toong

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 송금할 때 은행 앱을 연다. 설치돼 있지 않으면 Play 스토어에서 앱 이름으로 검색한다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "toong/bank_app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        val name = call.argument<String>("name") ?: ""
                        val launch = packageManager.getLaunchIntentForPackage(pkg)
                        if (launch != null) {
                            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(launch)
                            result.success("opened")
                        } else {
                            result.success(if (openStore(name)) "store" else "none")
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openStore(name: String): Boolean {
        val query = Uri.encode(name)
        for (uri in listOf(
            "market://search?q=$query&c=apps",
            "https://play.google.com/store/search?q=$query&c=apps",
        )) {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: ActivityNotFoundException) {
            }
        }
        return false
    }
}
