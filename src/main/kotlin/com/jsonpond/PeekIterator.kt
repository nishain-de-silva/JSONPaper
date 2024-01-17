package com.jsonpond

internal class PeekIterator(private val data: ByteArray): State() {
    private var position = 0
    fun hasNext(): Boolean {
        return data.size > position
    }

    fun peek(): Byte? {
        while (data.size > position) {
            val value = data[position+1]
            if (value > TAB) return value
        }
        return null
    }

    fun nextByte(): Byte {
        return data[position++]
    }

    fun moveBack() {
        position--
    }
}
