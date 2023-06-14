package JSONPond

internal open class State {
    companion object {
        const val COMMA: Byte = 44
        const val TAB: Byte = 32
        const val NEW_LINE: Byte = 10
        const val OPEN_OBJECT: Byte = 123
        const val OPEN_ARRAY: Byte = 91
        const val CLOSE_OBJECT: Byte = 125
        const val CLOSE_ARRAY: Byte = 93
        const val LETTER_N: Byte = 110
        const val LETTER_T: Byte = 116
        const val LETTER_F: Byte = 102
        const val COLON: Byte = 58
        const val DECIMAL: Byte = 46
        const val MINUS: Byte = 45
        const val ESCAPE: Byte = 92
    }

    internal var jsonText: String = ""
    internal var jsonData: ByteArray = byteArrayOf()
    internal var contentType: String = ""
    internal var extractInnerContent = false
    internal var intermediateSymbol: ByteArray = byteArrayOf(63, 63, 63)
    internal var errorHandler: ((ErrorInfo) -> Unit)? = null
    internal var errorInfo:  Pair<ErrorCode, Int>? = null
    internal var pathSplitter: Char = '.'
    internal var isBubbling: Boolean = false

    protected var QUOTATION: Byte = 34


}