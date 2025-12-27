package com.reactnativereadium.utils.extensions

import android.content.Context
import android.net.Uri
import org.readium.r2.shared.util.mediatype.MediaType
import com.reactnativereadium.utils.ContentResolverUtil
import java.io.File
import java.util.*

suspend fun Uri.copyToTempFile(context: Context, dir: String): File? {
    return try {
        val filename = UUID.randomUUID().toString()
        // In Readium 3.x, media type sniffing is done via AssetRetriever
        // For temp files, just use a default extension
        val path = "$dir$filename.tmp"
        ContentResolverUtil.getContentInputStream(context, this, path)
        File(path)
    } catch (e: Exception) {
        null
    }
}
