package com.jsonpond

internal class PeekIterator(private val data: ByteArray) {
    private var position = 0
    fun hasNext(): Boolean {
        return data.size > position
    }

    fun nextByte(): Byte {
        return data[position++]
    }

    fun moveBack() {
        position--
    }
}
