package com.example.sms_rag
import android.Manifest
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "sms_reader/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllSms" -> {
                    val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
                    if (!granted) {
                        result.error("PERMISSION_DENIED", "READ_SMS permission not granted", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val smsList = querySmsInbox()
                        result.success(smsList)
                    } catch (e: Exception) {
                        result.error("FAILED", "Failed to read SMS: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun querySmsInbox(): ArrayList<Map<String, Any?>> {
        val smsUri: Uri = Uri.parse("content://sms/inbox")
        val projection = arrayOf("_id", "address", "body", "date", "type")
        val smsList = ArrayList<Map<String, Any?>>()

        val cursor: Cursor? = contentResolver.query(smsUri, projection, null, null, "date DESC")
        cursor?.use { c ->
            val idIdx = c.getColumnIndex("_id")
            val addrIdx = c.getColumnIndex("address")
            val bodyIdx = c.getColumnIndex("body")
            val dateIdx = c.getColumnIndex("date")
            val typeIdx = c.getColumnIndex("type")
            while (c.moveToNext()) {
                val map = mapOf<String, Any?>(
                    "id" to if (idIdx >= 0) c.getLong(idIdx) else null,
                    "address" to if (addrIdx >= 0) c.getString(addrIdx) else null,
                    "body" to if (bodyIdx >= 0) c.getString(bodyIdx) else null,
                    "date" to if (dateIdx >= 0) c.getLong(dateIdx) else null,
                    "type" to if (typeIdx >= 0) c.getInt(typeIdx) else null
                )
                smsList.add(map)
            }
        }
        return smsList
    }
}