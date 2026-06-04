package com.example.flutter_webcam_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Build
import android.util.Log
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.Executors

class WebcamService : LifecycleService() {

    private val TAG = "WebcamService"
    private var serverSocket: ServerSocket? = null
    private var discoverySocket: DatagramSocket? = null
    private var clientSocket: Socket? = null
    private var outputStream: OutputStream? = null
    
    private val socketExecutor = Executors.newSingleThreadExecutor()
    private val discoveryExecutor = Executors.newSingleThreadExecutor()
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    private var targetWidth = 1280
    private var targetHeight = 720
    private var targetFps = 30
    private var targetRotation = 0
    private var codecMode = "MJPEG"
    private var jpegQuality = 70
    private var lastFrameTime = 0L

    // Pre-allocate out stream to stop GC thrashing
    private val mjpegOutputStream = ByteArrayOutputStream(1024 * 500)

    override fun onCreate() {
        super.onCreate()
        startForegroundService()
        startServer()
        startDiscoveryServer()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return super.onStartCommand(intent, flags, startId)
    }

    private fun startForegroundService() {
        val channelId = "webcam_service_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Webcam Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Webcam Service")
            .setContentText("Streaming MJPEG to PC...")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .build()

        startForeground(1, notification)
    }

    private fun startServer() {
        socketExecutor.execute {
            try {
                serverSocket = ServerSocket(8080)
                Log.i(TAG, "Server listening on port 8080")
                while (!Thread.interrupted()) {
                    val client = serverSocket!!.accept()
                    Log.i(TAG, "Client connected: ${client.inetAddress}")
                    
                    try {
                        val reader = BufferedReader(InputStreamReader(client.getInputStream()))
                        val configLine = reader.readLine()
                        if (configLine != null && configLine.startsWith("CONFIG:")) {
                            val parts = configLine.substring(7).trim().split(",")
                            if (parts.size >= 4) {
                                targetWidth = parts[0].toInt()
                                targetHeight = parts[1].toInt()
                                targetFps = parts[2].toInt()
                                targetRotation = parts[3].toInt()
                                if (parts.size >= 5) {
                                    codecMode = parts[4].uppercase()
                                } else {
                                    codecMode = "MJPEG" // default
                                }
                                if (parts.size >= 6) {
                                    jpegQuality = parts[5].toIntOrNull() ?: 70
                                } else {
                                    jpegQuality = 70
                                }
                                Log.i(TAG, "Received Config: ${targetWidth}x${targetHeight} ${targetFps}fps ${targetRotation}deg $codecMode Q:$jpegQuality")
                                
                                startMjpegCamera()
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to read handshake", e)
                    }

                    synchronized(this) {
                        clientSocket?.close()
                        clientSocket = client
                        outputStream = client.getOutputStream()
                    }

                    Thread {
                        try {
                            while (client.getInputStream().read() != -1) {}
                        } catch (e: Exception) {}
                        Log.i(TAG, "Client disconnected")
                        stopCamera()
                    }.start()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Socket error", e)
            }
        }
    }

    private fun startDiscoveryServer() {
        discoveryExecutor.execute {
            try {
                discoverySocket = DatagramSocket(8082)
                discoverySocket?.broadcast = true
                val buffer = ByteArray(256)
                while (!Thread.interrupted()) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    discoverySocket?.receive(packet)
                    val message = String(packet.data, 0, packet.length).trim()
                    if (message == "WEBCAM_DISCOVERY_PING") {
                        val reply = "WEBCAM_DISCOVERY_PONG".toByteArray()
                        val replyPacket = DatagramPacket(reply, reply.size, packet.address, packet.port)
                        discoverySocket?.send(replyPacket)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Discovery socket error", e)
            }
        }
    }

    private fun stopCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            try { cameraProviderFuture.get().unbindAll() } catch (e: Exception) {}
        }, ContextCompat.getMainExecutor(this))
        synchronized(this) {
            outputStream = null
            clientSocket?.close()
            clientSocket = null
        }
    }

    private fun startMjpegCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()
            
            val builder = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            
            if (targetWidth > 0 && targetHeight > 0) {
                if (targetRotation == 0 || targetRotation == 180) {
                    builder.setTargetResolution(android.util.Size(targetHeight, targetWidth))
                } else {
                    builder.setTargetResolution(android.util.Size(targetWidth, targetHeight))
                }
            }
            
            val rotationInt = when (targetRotation) {
                90 -> android.view.Surface.ROTATION_90
                180 -> android.view.Surface.ROTATION_180
                270 -> android.view.Surface.ROTATION_270
                else -> android.view.Surface.ROTATION_0
            }
            builder.setTargetRotation(rotationInt)

            val imageAnalysis = builder.build()

            imageAnalysis.setAnalyzer(analysisExecutor) { imageProxy ->
                processImage(imageProxy)
            }
            
            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            try {
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(this, cameraSelector, imageAnalysis)
            } catch (exc: Exception) {
                Log.e(TAG, "Use case binding failed", exc)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private var nv21Buffer: ByteArray? = null

    private fun processImage(image: ImageProxy) {
        val currentTime = System.currentTimeMillis()
        if (targetFps > 0) {
            val minInterval = 1000 / targetFps
            if (currentTime - lastFrameTime < minInterval) {
                image.close()
                return
            }
        }
        lastFrameTime = currentTime

        if (image.format != ImageFormat.YUV_420_888) {
            image.close()
            return
        }

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer

        val width = image.width
        val height = image.height
        val yRowStride = yPlane.rowStride
        val uvRowStride = uPlane.rowStride
        val uvPixelStride = uPlane.pixelStride

        val nv21Size = width * height * 3 / 2
        if (nv21Buffer == null || nv21Buffer!!.size != nv21Size) {
            nv21Buffer = ByteArray(nv21Size)
        }
        val nv21 = nv21Buffer!!

        var pos = 0
        yBuffer.position(0)
        if (yRowStride == width) {
            yBuffer.get(nv21, 0, width * height)
            pos += width * height
        } else {
            for (row in 0 until height) {
                yBuffer.position(row * yRowStride)
                val bytesToRead = Math.min(width, yBuffer.remaining())
                yBuffer.get(nv21, pos, bytesToRead)
                pos += width
            }
        }

        val uvHeight = height / 2
        val uvWidth = width / 2
        
        vBuffer.position(0)
        uBuffer.position(0)

        if (uvPixelStride == 2 && uvRowStride == width) {
            val lengthToCopy = Math.min(width * uvHeight, vBuffer.remaining())
            vBuffer.get(nv21, pos, lengthToCopy)
        } else {
            val vCap = vBuffer.capacity()
            val uCap = uBuffer.capacity()
            for (row in 0 until uvHeight) {
                val rowOffset = row * uvRowStride
                for (col in 0 until uvWidth) {
                    val index = rowOffset + col * uvPixelStride
                    nv21[pos++] = if (index < vCap) vBuffer.get(index) else 0
                    nv21[pos++] = if (index < uCap) uBuffer.get(index) else 0
                }
            }
        }

        val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        mjpegOutputStream.reset() // Reuse buffer!
        yuvImage.compressToJpeg(Rect(0, 0, width, height), jpegQuality, mjpegOutputStream)
        val jpegBytes = mjpegOutputStream.toByteArray()

        synchronized(this) {
            try {
                if (outputStream != null) {
                    val lengthBytes = ByteBuffer.allocate(4).putInt(jpegBytes.size).array()
                    outputStream?.write(lengthBytes)
                    outputStream?.write(jpegBytes)
                    outputStream?.flush()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send JPEG", e)
            }
        }
        
        image.close()
    }

    override fun onDestroy() {
        super.onDestroy()
        serverSocket?.close()
        discoverySocket?.close()
        clientSocket?.close()
        socketExecutor.shutdown()
        discoveryExecutor.shutdown()
        analysisExecutor.shutdown()
    }
}
