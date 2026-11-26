package com.miya.nusantara_hybrid_pos

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.speech.tts.TextToSpeech
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.OutputStream
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.miya.nusantara_hybrid_pos/thermal_printer"
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private var tts: TextToSpeech? = null
    private var ttsReady: Boolean = false

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
                ttsReady = true
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1002)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAndRequestPermissions" -> {
                    val hasPerms = checkAndRequestPermissions()
                    result.success(hasPerms)
                }
                "getPairedDevices" -> {
                    try {
                        val devices = getPairedDevices()
                        result.success(devices)
                    } catch (e: Exception) {
                        result.error("DEVICE_ERROR", e.message, null)
                    }
                }
                "printBytes" -> {
                    val address = call.argument<String>("address")
                    val bytes = call.argument<ByteArray>("bytes")

                    if (address.isNullOrEmpty() || bytes == null) {
                        result.error("INVALID_ARGS", "Device address or bytes is missing", null)
                        return@setMethodCallHandler
                    }

                    printBytesAsync(address, bytes, result)
                }
                "saveAndSharePdf" -> {
                    val fileName = call.argument<String>("fileName")
                    val bytes = call.argument<ByteArray>("bytes")

                    if (fileName.isNullOrEmpty() || bytes == null) {
                        result.error("INVALID_ARGS", "File name or bytes is missing", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val path = saveAndSharePdf(fileName, bytes)
                        result.success(path)
                    } catch (e: Exception) {
                        result.error("PDF_SAVE_ERROR", e.localizedMessage ?: e.message, null)
                    }
                }
                "openWhatsAppWithQr" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    val qrPngBytes = call.argument<ByteArray>("qrPngBytes")

                    try {
                        val ok = openWhatsAppWithQr(phone, message, qrPngBytes)
                        result.success(ok)
                    } catch (e: Exception) {
                        result.error("WHATSAPP_ERROR", e.localizedMessage ?: e.message, null)
                    }
                }
                "showOrderReadyNotification" -> {
                    val title = call.argument<String>("title") ?: "Order Ready for Pickup!"
                    val body = call.argument<String>("body") ?: "Please proceed to the counter to collect your order."
                    try {
                        showOrderReadyNotification(title, body)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "speakText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val repeatCount = call.argument<Int>("repeatCount") ?: 2
                    if (text.isNotEmpty() && ttsReady) {
                        tts?.language = Locale.US
                        tts?.setPitch(1.05f)
                        tts?.setSpeechRate(0.84f)
                        val params = Bundle().apply {
                            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
                        }
                        val count = repeatCount.coerceIn(1, 3)
                        for (i in 0 until count) {
                            val mode = if (i == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
                            tts?.speak(text, mode, params, "queue_${System.currentTimeMillis()}_$i")
                            if (i < count - 1) {
                                tts?.playSilentUtterance(650, TextToSpeech.QUEUE_ADD, "pause_${System.currentTimeMillis()}_$i")
                            }
                        }
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }

    private fun checkAndRequestPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val connectGranted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED

            val scanGranted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED

            if (!connectGranted || !scanGranted) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.BLUETOOTH_CONNECT,
                        Manifest.permission.BLUETOOTH_SCAN
                    ),
                    101
                )
                return false
            }
            return true
        } else {
            val btGranted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH
            ) == PackageManager.PERMISSION_GRANTED

            val adminGranted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_ADMIN
            ) == PackageManager.PERMISSION_GRANTED

            if (!btGranted || !adminGranted) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.BLUETOOTH,
                        Manifest.permission.BLUETOOTH_ADMIN
                    ),
                    102
                )
                return false
            }
            return true
        }
    }

    private fun getPairedDevices(): List<Map<String, String>> {
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED
            ) {
                return emptyList()
            }
        }

        val bondedDevices: Set<BluetoothDevice>? = adapter.bondedDevices
        val list = mutableListOf<Map<String, String>>()

        bondedDevices?.forEach { device ->
            val name = try {
                device.name ?: "Unknown Printer"
            } catch (e: SecurityException) {
                "Unknown Printer"
            }
            list.add(
                mapOf(
                    "name" to name,
                    "address" to device.address
                )
            )
        }

        return list
    }

    private fun printBytesAsync(address: String, bytes: ByteArray, result: MethodChannel.Result) {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) {
            result.error("NO_BLUETOOTH", "Bluetooth is not supported on this device", null)
            return
        }

        if (!adapter.isEnabled) {
            result.error("BLUETOOTH_DISABLED", "Bluetooth is turned off. Please turn on Bluetooth.", null)
            return
        }

        Thread {
            var socket: BluetoothSocket? = null
            var outStream: OutputStream? = null
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.BLUETOOTH_CONNECT)
                        != PackageManager.PERMISSION_GRANTED
                    ) {
                        runOnUiThread {
                            result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission not granted", null)
                        }
                        return@Thread
                    }
                }

                val device = adapter.getRemoteDevice(address)

                // 1. Cancel discovery before connecting (critical for RFCOMM connection stability)
                try {
                    adapter.cancelDiscovery()
                } catch (_: Exception) {}

                // 2. Connect with automatic fallback from secure to insecure RFCOMM
                try {
                    socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                    socket.connect()
                } catch (e1: Exception) {
                    try {
                        socket?.close()
                    } catch (_: Exception) {}
                    // Many portable thermal printers require insecure RFCOMM after OS pairing
                    socket = device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                    socket.connect()
                }

                outStream = socket.outputStream

                // 3. Send ESC @ (printer initialize)
                val initCmd = byteArrayOf(0x1B, 0x40)
                outStream.write(initCmd)
                outStream.flush()
                Thread.sleep(25)

                // 4. Chunked write in 256-byte chunks with 25ms delay to prevent UART buffer overflow
                val chunkSize = 256
                var offset = 0
                while (offset < bytes.size) {
                    val length = Math.min(chunkSize, bytes.size - offset)
                    outStream.write(bytes, offset, length)
                    outStream.flush()
                    offset += length
                    if (offset < bytes.size) {
                        Thread.sleep(25)
                    }
                }

                // 5. Write 4 trailing line feeds so receipt feeds past the manual tear bar
                val trailingFeeds = byteArrayOf(0x0A, 0x0A, 0x0A, 0x0A)
                outStream.write(trailingFeeds)
                outStream.flush()

                // 6. Wait 700ms before closing socket so Bluetooth radio hardware finishes transmission
                Thread.sleep(700)

                runOnUiThread {
                    result.success(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "PRINT_FAILED",
                        "Gagal menghubungkan atau mencetak ke printer thermal ($address): ${e.localizedMessage ?: e.message}",
                        null
                    )
                }
            } finally {
                try {
                    outStream?.close()
                } catch (_: Exception) {}
                try {
                    socket?.close()
                } catch (_: Exception) {}
            }
        }.start()
    }

    private fun saveAndSharePdf(fileName: String, bytes: ByteArray): String {
        var fileUri: Uri? = null
        var displayLocation = ""

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }

            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                ?: throw Exception("Tidak dapat membuat file PDF di folder Downloads MediaStore")

            resolver.openOutputStream(uri)?.use { os ->
                os.write(bytes)
                os.flush()
            }

            fileUri = uri
            displayLocation = "Downloads/$fileName"
        } else {
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) {
                downloadsDir.mkdirs()
            }
            val targetFile = File(downloadsDir, fileName)
            targetFile.writeBytes(bytes)

            fileUri = Uri.fromFile(targetFile)
            displayLocation = targetFile.absolutePath
        }

        if (fileUri != null) {
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(fileUri, "application/pdf")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            try {
                val chooser = Intent.createChooser(viewIntent, "Buka Z-Report PDF")
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(chooser)
            } catch (_: Exception) {
                // Fallback to SEND share intent if VIEW has no handler
                try {
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "application/pdf"
                        putExtra(Intent.EXTRA_STREAM, fileUri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    val chooser = Intent.createChooser(shareIntent, "Bagikan Z-Report PDF")
                    chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(chooser)
                } catch (_: Exception) {}
            }
        }

        return displayLocation
    }

    private fun openWhatsAppWithQr(phone: String, message: String, qrPngBytes: ByteArray?): Boolean {
        val cleanPhone = phone.replace(Regex("[^0-9]"), "")

        if (qrPngBytes != null && qrPngBytes.isNotEmpty()) {
            var imageUri: Uri? = null
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val fileName = "QR_Order_${System.currentTimeMillis()}.png"
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                        put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
                        put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/NusantaraPOS")
                    }
                    imageUri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    if (imageUri != null) {
                        contentResolver.openOutputStream(imageUri)?.use { os ->
                            os.write(qrPngBytes)
                            os.flush()
                        }
                    }
                }
            } catch (_: Exception) {
                imageUri = null
            }

            if (imageUri != null) {
                val waPackages = listOf("com.whatsapp", "com.whatsapp.w4b")
                for (pkg in waPackages) {
                    try {
                        val sendIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "image/png"
                            putExtra(Intent.EXTRA_STREAM, imageUri)
                            putExtra(Intent.EXTRA_TEXT, message)
                            if (cleanPhone.isNotEmpty()) {
                                putExtra("jid", "$cleanPhone@s.whatsapp.net")
                            }
                            setPackage(pkg)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(sendIntent)
                        return true
                    } catch (_: Exception) {
                        // Try next WhatsApp package or fallback to wa.me
                    }
                }
            }
        }

        // Fallback: Direct wa.me URL opens customer's WhatsApp chat with full message + live tracker link
        val waUrl = if (cleanPhone.isNotEmpty()) {
            "https://wa.me/$cleanPhone?text=${Uri.encode(message)}"
        } else {
            "https://wa.me/?text=${Uri.encode(message)}"
        }
        val viewIntent = Intent(Intent.ACTION_VIEW, Uri.parse(waUrl)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(viewIntent)
        return true
    }

    private fun showOrderReadyNotification(title: String, body: String) {
        val channelId = "nusantara_order_ready_channel"
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Notifikasi Pesanan Siap Diambil",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alarm dan notifikasi WhatsApp/Counter saat pesanan siap diambil"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .build()

        notificationManager.notify((System.currentTimeMillis() % 100000).toInt(), notification)
    }
}
