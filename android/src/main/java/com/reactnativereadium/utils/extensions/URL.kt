package com.reactnativereadium.utils.extensions

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.util.*

suspend fun URL.download(path: String): File? {
    return try {
        val file = File(path)
        withContext(Dispatchers.IO) {
            openStream().use { input ->
                FileOutputStream(file).use { output ->
                    input.copyTo(output)
                }
            }
        }
        file
    } catch (e: Exception) {
        null
    }
}

suspend fun URL.copyToTempFile(dir: String): File? {
    return try {
        val filename = UUID.randomUUID().toString()
        // Extract extension from URL path
        val extension = this.path.substringAfterLast('.', "tmp")
        val path = "$dir$filename.$extension"
        download(path)
    } catch (e: Exception) {
        null
    }
}
