package com.moonbit.openseek

import java.io.BufferedInputStream
import java.io.DataInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.zip.GZIPInputStream

/**
 * Reads a Browser release archive (`tar -czf … browser`). Android ships no tar
 * reader; this one accepts the ustar, GNU long-name and pax path records that
 * GNU tar and bsdtar write, and nothing that could leave the target directory.
 */
internal object BundleArchive {
    class Malformed(message: String) : IOException(message)

    private const val BLOCK = 512

    /** openseek-api's precompressed copies; the WebView reads the originals. */
    private val skipped = Regex(""".*\.(br|gz)$""")

    /**
     * Extracts the files under the archive's single top-level directory into
     * [target]. Reads the gzip stream to its end, so its CRC covers the whole
     * download.
     */
    fun extract(gzip: InputStream, target: File) {
        val input = DataInputStream(GZIPInputStream(BufferedInputStream(gzip)))
        val header = ByteArray(BLOCK)
        var longPath: String? = null
        while (true) {
            input.readFully(header)
            if (header.all { it == 0.toByte() }) break
            val size = size(header)
            when (header[156].toInt().toChar()) {
                'L' -> {
                    longPath = String(data(input, size), Charsets.UTF_8).trimEnd('\u0000')
                    continue
                }
                'x' -> {
                    longPath = paxPath(data(input, size)) ?: longPath
                    continue
                }
                'g' -> {
                    skipEntry(input, size)
                    continue
                }
            }
            val path = longPath ?: headerPath(header)
            longPath = null
            val type = header[156].toInt().toChar()
            val relative = relative(path)
            when {
                type == '5' -> {
                    relative?.let { File(target, it).mkdirs() }
                    skipEntry(input, size)
                }
                type != '0' && type != '\u0000' && type != '7' -> throw Malformed("unsupported entry $path")
                relative == null || skipped.matches(relative) -> skipEntry(input, size)
                else -> {
                    val file = File(target, relative)
                    file.parentFile?.mkdirs()
                    file.outputStream().use { copy(input, it, size) }
                    copy(input, null, padding(size))
                }
            }
        }
        val rest = ByteArray(8 * 1024)
        while (input.read(rest) >= 0) Unit
    }

    /** The path below the top-level directory, or null for that directory itself. */
    private fun relative(path: String): String? {
        val segments = path.trimEnd('/').split('/')
        if (path.startsWith("/") || segments.any { it.isEmpty() || it == "." || it == ".." }) {
            throw Malformed("unsafe entry $path")
        }
        return segments.drop(1).takeIf { it.isNotEmpty() }?.joinToString("/")
    }

    private fun headerPath(header: ByteArray): String {
        val name = field(header, 0, 100)
        val prefix = if (field(header, 257, 6).startsWith("ustar")) field(header, 345, 155) else ""
        return if (prefix.isEmpty()) name else "$prefix/$name"
    }

    /** The `path` record of a pax extended header: `<length> path=<value>\n`. */
    private fun paxPath(records: ByteArray): String? = String(records, Charsets.UTF_8).lineSequence()
        .mapNotNull { it.substringAfter(' ', "").takeIf { record -> record.startsWith("path=") } }
        .lastOrNull()?.removePrefix("path=")

    private fun field(header: ByteArray, offset: Int, length: Int): String {
        var end = offset
        while (end < offset + length && header[end] != 0.toByte()) end++
        return String(header, offset, end - offset, Charsets.UTF_8)
    }

    private fun size(header: ByteArray): Long {
        if (header[124].toInt() and 0x80 != 0) throw Malformed("entry too large")
        val digits = field(header, 124, 12).trim()
        return if (digits.isEmpty()) 0 else digits.toLongOrNull(8) ?: throw Malformed("bad entry size")
    }

    private fun padding(size: Long): Long = (BLOCK - size % BLOCK) % BLOCK

    private fun data(input: DataInputStream, size: Long): ByteArray {
        if (size > 1 shl 20) throw Malformed("header record too large")
        val bytes = ByteArray(size.toInt())
        input.readFully(bytes)
        copy(input, null, padding(size))
        return bytes
    }

    /** Skips an entry's data and the padding that fills its last block. */
    private fun skipEntry(input: DataInputStream, size: Long) = copy(input, null, size + padding(size))

    private fun copy(input: DataInputStream, output: OutputStream?, size: Long) {
        val buffer = ByteArray(64 * 1024)
        var left = size
        while (left > 0) {
            val read = input.read(buffer, 0, minOf(left, buffer.size.toLong()).toInt())
            if (read < 0) throw Malformed("archive ends inside an entry")
            output?.write(buffer, 0, read)
            left -= read
        }
    }
}
