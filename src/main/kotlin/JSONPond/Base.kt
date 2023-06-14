package JSONPond

internal class ByteWrapper(var bytes: ByteArray) {
    operator fun plusAssign(byteArray: ByteArray) {
        bytes = bytes.plus(byteArray)
    }

    operator fun plusAssign(byte: Byte) {
        bytes = bytes.plus(byte)
    }

    fun dropLast(): ByteArray {
        bytes = bytes.copyOf(bytes.lastIndex)
        return bytes
    }

    fun last(): Byte {
        return bytes.last()
    }
}
internal data class ValueType(val value: ValueStore, val type: String)
internal class ValueStore {
    var string: String = ""
    var bytes: ByteArray = byteArrayOf()
    var array: Array<JSONBlock> = arrayOf()
    var children: Array<JSONChild> = arrayOf()
    var tree: Any = listOf(0)

    constructor(input: String) {
        string = input
    }

    constructor(text: String, data: ByteArray) {
        string = text
        bytes = data
    }

    constructor(arrayData: Array<JSONBlock>) {
        array = arrayData
    }

    constructor(childData: Array<JSONChild>) {
        children = childData
    }

    constructor(data: ByteWrapper) {
        bytes = data.bytes
    }

    constructor(parsedData: Any) {
        tree = parsedData
    }
}
internal enum class UpdateMode {
    upsert,
    onlyUpdate,
    onlyInsert,
    delete
}

@Suppress("FunctionName")
internal open class Base: State() {

    private class CollectionHolder(isObject: Boolean) {
        var type: String
        var objectCollection: MutableMap<String, Any>
        var arrayCollection: MutableList<Any>
        var reservedObjectKey = ""

        init {
            type = if (isObject) "object" else "array"
            objectCollection = mutableMapOf()
            arrayCollection = mutableListOf()
        }

        fun assignChildToObject(child: CollectionHolder) {
            objectCollection[reservedObjectKey] = if (child.type == "object") child.objectCollection else child.arrayCollection
        }

        fun appendChildToArray(child: CollectionHolder) {
            arrayCollection += if (child.type == "object") child.objectCollection else child.arrayCollection
        }
    }
    
    companion object {
        private fun List<ByteArray>.joined(seperator: ByteArray): ByteArray {
            var finalArray = byteArrayOf()
            if(isEmpty()) {
                return finalArray
            }
            for (index in 0 until this.lastIndex) {
                finalArray += this[index]
                finalArray += seperator
            }
            finalArray += this.last()
            return finalArray
        }
        fun fillTab(repeatCount: Int) : ByteArray {
            val array = ByteArray(repeatCount)
            array.fill(TAB)
            return  array
        }
        internal fun _serializeToBytes(node: Any?, index: Int, tabCount: Int, stringDelimiter: Byte) : ByteArray {
            when (node) {
                is Map<*, *> -> {
                    val innerContent: List<ByteArray> = node.map {
                        byteArrayOf(stringDelimiter) +
                                it.key.toString().toByteArray() +
                                (if (tabCount != 0) byteArrayOf(stringDelimiter,
                                    COLON,
                                    TAB
                                ) else byteArrayOf(
                                    stringDelimiter, COLON
                                )) +
                                _serializeToBytes(it.value, index + 1, tabCount, stringDelimiter)
                    }

                    if (tabCount != 0 && innerContent.isNotEmpty()) {
                        val spacer: ByteArray = fillTab((index + 1) * tabCount)
                        val endSpacer: ByteArray = fillTab(index * tabCount)
                        var data: ByteArray = byteArrayOf(OPEN_OBJECT, NEW_LINE)
                        val seperator: ByteArray = byteArrayOf(COMMA, NEW_LINE) + spacer
                        data += spacer
                        data += innerContent.joined(seperator)
                        data += NEW_LINE
                        data += endSpacer
                        data += CLOSE_OBJECT
                        return data
                    }
                    return (byteArrayOf(OPEN_OBJECT) + (innerContent.joined(byteArrayOf(
                        COMMA
                    )))) + byteArrayOf(CLOSE_OBJECT)
                }
                is List<*> -> {
                    val innerContent = node.map { _serializeToBytes(it, index + 1, tabCount, stringDelimiter) }
                    if (tabCount != 0 && innerContent.isNotEmpty()) {
                        val spacer: ByteArray = fillTab((index + 1) * tabCount)
                        val endSpacer: ByteArray = fillTab(index * tabCount)
                        var data: ByteArray = byteArrayOf(OPEN_ARRAY, NEW_LINE)
                        val separator: ByteArray = byteArrayOf(COMMA, NEW_LINE) + spacer
                        data += spacer
                        data += innerContent.joined(separator)
                        data += NEW_LINE
                        data += endSpacer
                        data += CLOSE_ARRAY
                        return data
                    }
                    return (byteArrayOf(OPEN_ARRAY) + innerContent.joined(byteArrayOf(
                        COMMA
                    ))) + byteArrayOf(CLOSE_ARRAY)
                }
                is String -> {
                    return byteArrayOf(stringDelimiter) + node.toByteArray() + stringDelimiter
                }
                is Boolean -> {
                    return if (node) byteArrayOf(LETTER_T, 114, 117, 101) else byteArrayOf(
                        LETTER_F, 97, 108, 115, 101)
                }
                is Number -> {
                    return node.toString().toByteArray()
                }
                null -> {
                    return byteArrayOf(LETTER_N, 117, 108, 108)
                }
                else -> {
                    return byteArrayOf(stringDelimiter, 35, 73, 78, 86, 65, 76, 73, 68, 95, 84, 89, 80, 69, stringDelimiter)
                }
            }
        }
    }

    internal fun <T> getField(path: String?, fieldName: String, mapper: (ValueStore) -> T?, ignoreType: Boolean = false) : T? {
        val (data, type) = if (path == null) ValueType(
            ValueStore(
                jsonText,
                jsonData
            ), contentType
        ) else decodeData(path) ?: return null
        if ((!ignoreType && type != fieldName) ||  (ignoreType && type != fieldName && type != "string")){
            if(errorHandler != null) {
                errorHandler?.invoke(
                    ErrorInfo(
                        ErrorCode.nonMatchingDataType,
                        (path?.split(pathSplitter)?.size ?: 0) - 1,
                        path ?: ""
                    )
                )
            }
            return null
        }
        return mapper(data)
    }

    internal fun _prettyifyContent(originalContent: ByteArray) : String {
        var presentation = byteArrayOf()
        var notationBalance = 0
        var isEscaping = false
        var isQuotes = false

        if (originalContent[1] == NEW_LINE) {
            return originalContent.decodeToString() // already being pretty
        }
        for (char in originalContent) {
            if (!isEscaping && char == QUOTATION) {
                isQuotes = !isQuotes
            } else if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                    presentation += char
                    presentation += NEW_LINE
                    presentation += fillTab(notationBalance * 3)
                    continue
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    presentation += NEW_LINE
                    presentation += fillTab(notationBalance * 3)
                } else if (char == COMMA) {
                    presentation += char
                    presentation += NEW_LINE
                    presentation += fillTab(notationBalance * 3)
                    continue
                } else if (char == COLON) {
                    presentation += char
                    presentation += TAB
                    continue
                }
            }

            if (isEscaping) {
                isEscaping = false
            } else if (char == ESCAPE) {
                isEscaping = true
            }
            presentation += char
        }
        return presentation.decodeToString()
    }

    internal fun resolveValue(stringData: String, byteData: ByteArray, type: String) : Any {
        return when ((type)) {
            "number" -> stringData.toDouble()
            "array" -> JSONBlock(byteData, "array").collection()!!
            "boolean" -> stringData == "true"
            "null" -> Constants.NULL
            else -> stringData
        }
    }
    internal fun identifyStringDelimiter(text: String) {
        for (char in text) {
            if(char == '"' || char == '\'') {
                QUOTATION = if(char == '"')  34 else 39
                break
            }
        }
    }
    internal fun decodeData(
        inputPath: String,
        copyCollectionData: Boolean = false,
        grabAllPaths: Boolean = false
    ) : ValueType? {
        val results = exploreData(
            inputPath,
            copyCollectionData,
            grabAllPaths)
        errorInfo?.apply {
            errorHandler?.invoke(ErrorInfo(this.first, this.second, inputPath))
            errorHandler = null
        }
        return results
    }

    private fun _singleItemList(source: JSONBlock): ValueType {
        return ValueType(ValueStore(arrayOf(source)), "CODE_ALL")
    }

    private fun exploreData(
        inputPath: String,
        copyCollectionData: Boolean,
        grabAllPaths: Boolean
    ) : ValueType? {
        errorInfo = null
        if (!(contentType == "object" || contentType == "array")) {
            errorInfo = Pair(ErrorCode.nonNestableRootType, 0)
            return null
        }

        fun <T> Array<T>.dropLast() : Array<T> {
            return this.copyOfRange(0, lastIndex)
        }
        val splitValues = _splitPath(inputPath)
        val paths: MutableList<ByteArray> = splitValues.first
        val lightMatch: List<Boolean> = splitValues.second
        var processedPathIndex = 0
        var isNavigatingUnknownPath = false
        var advancedOffset = 0
        var traversalHistory: Array<Pair<Int, Int>> = arrayOf()
        var isInQuotes = false
        var startSearchValue = false
        var isGrabbingText = false
        var grabbedText = ""
        var grabbedBytes: ByteWrapper
        var grabbingKey: ByteArray = byteArrayOf()
        var needProcessKey = false
        var isGrabbingKey = false
        var notationBalance = 0
        var grabbingDataType: String
        var escapeCharacter = false
        var commonPathCollections: Array<JSONBlock> = arrayOf()

        fun restoreLastPointIfNeeded(): Boolean {
            if (traversalHistory.isNotEmpty()){
                traversalHistory[traversalHistory.size - 1].apply {
                    processedPathIndex = this.first
                    advancedOffset = this.second
                }
                startSearchValue = false
                isNavigatingUnknownPath = true
                return true
            }
            return false
        }

        if (paths.size == 0 && !copyCollectionData) {
            errorInfo = Pair(ErrorCode.emptyQueryPath, -1)
            return null
        }
        if (paths.lastOrNull().contentEquals(intermediateSymbol)) {
            errorInfo = Pair(ErrorCode.captureUnknownElement, paths.size - 1)
            return null
        }
        val iterator = jsonData.iterator()
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            // if within quotation ignore processing json literals...
            if (!isInQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                    // if the last value of last key is object or array then start copy it
                    if (processedPathIndex == paths.size) {
                        if (extractInnerContent) {
                            return _getStructuredData(iterator, firstCharacter = char)
                        }
                        if (copyCollectionData) {
                            if (char == OPEN_OBJECT) {
                                return ValueType(
                                    ValueStore(
                                        childData = _getObjectEntries(
                                            iterator
                                        )
                                    ), "CODE_COLLECTION"
                                )
                            }
                            return ValueType(
                                ValueStore(
                                    childData = _getArrayValues(
                                        iterator
                                    )
                                ), "CODE_COLLECTION"
                            )
                        }
                        grabbedBytes = ByteWrapper(byteArrayOf(char))
                        grabbingDataType = if (char == OPEN_OBJECT) "object" else "array"
                        _grabData(grabbedBytes, iterator)
                        if (grabAllPaths) {
                            if (restoreLastPointIfNeeded()) {
                                commonPathCollections += JSONBlock(grabbedBytes.bytes, grabbingDataType, this)
                                continue
                            }
                            return _singleItemList(JSONBlock(grabbedBytes.bytes, grabbingDataType))
                        }
                        return ValueType(
                            ValueStore(grabbedBytes),
                            grabbingDataType
                        )
                    }
                    if (paths[processedPathIndex].contentEquals(intermediateSymbol)) {
                        isNavigatingUnknownPath = true
                        traversalHistory += Pair(processedPathIndex, advancedOffset)
                        paths.removeAt(processedPathIndex)
                    }
                    // initiate elements counting inside array on reaching open bracket...
                    if (char == OPEN_ARRAY && ((advancedOffset + 1) == notationBalance || isNavigatingUnknownPath)) {
                        val parsedIndex = _toNumber(paths[processedPathIndex])
                        // occur when trying to access element of array with non-number index
                        if (parsedIndex == null) {
                            if (isNavigatingUnknownPath || restoreLastPointIfNeeded()) { continue }
                            errorInfo = Pair(ErrorCode.invalidArrayIndex, processedPathIndex)
                            return null
                        }
                        if (isNavigatingUnknownPath) {
                            isNavigatingUnknownPath = false
                            advancedOffset = notationBalance - 1
                        }
                        if (!_iterateArray(iterator, elementIndex = parsedIndex)) {
                            if (traversalHistory.isNotEmpty()) {
                                if (traversalHistory.size != 1) {
                                    traversalHistory = traversalHistory.dropLast()
                                    paths.add(processedPathIndex, intermediateSymbol)
                                }
                                traversalHistory[traversalHistory.size - 1].apply {
                                    processedPathIndex = this.first
                                    advancedOffset = this.second
                                }
                                isNavigatingUnknownPath = true
                                continue
                            }
                            errorInfo = Pair(ErrorCode.arrayIndexNotFound, processedPathIndex)
                            return null
                        }
                        processedPathIndex += 1
                        advancedOffset += 1
                        startSearchValue = true
                    } else {
                        // move to next nest object and start looking attribute key on next nested object...
                        startSearchValue = false
                    }
                    continue
                }
                if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    // occur after all element in focused array or object is finished searching...
                    if (notationBalance <= advancedOffset) {

                        // first - processedPathIndex
                        // second - advancedOffset
                        if (traversalHistory.isNotEmpty()) {
                            if (traversalHistory.last().second <= advancedOffset) {
                                paths.add(traversalHistory.last().first, intermediateSymbol)
                                traversalHistory = traversalHistory.dropLast()

                                if(traversalHistory.isEmpty()) {
                                    if (grabAllPaths) {
                                        return ValueType(
                                            ValueStore(
                                                commonPathCollections
                                            ), "CODE_ALL"
                                        )
                                    }
                                    errorInfo = Pair(ErrorCode.cannotFindElement, notationBalance)
                                    return null
                                }
                            }
                            traversalHistory.last().apply {
                                processedPathIndex = this.first
                                advancedOffset = this.second
                            }
                            isNavigatingUnknownPath = true
                            continue
                        }
                        errorInfo = Pair(
                            if (char == CLOSE_OBJECT)  ErrorCode.objectKeyNotFound else ErrorCode.arrayIndexNotFound,
                            notationBalance
                        )
                        return null
                    }
                    continue
                }
            }
            // ======== FINISHED HANDING JSON OPEN AND CLOSE NOTATION ==========
            if (startSearchValue) {
                if (notationBalance == advancedOffset) {
                    // ====== HANDLING GRABBING STRINGS =========
                    // ignore escaped double quotation characters inside string values...
                    if (!escapeCharacter && char == QUOTATION) {
                        isInQuotes = !isInQuotes
                        // if not the last processed value skip capturing value
                        if (processedPathIndex != paths.size) {
                            if(restoreLastPointIfNeeded()) {
                                continue
                            }
                            errorInfo = Pair(ErrorCode.nonNestedParent, processedPathIndex - 1)
                            return null
                        }
                        isGrabbingText = !isGrabbingText
                        if (!isGrabbingText) {
                            if (grabAllPaths) {
                                if (restoreLastPointIfNeeded()) {
                                    commonPathCollections += JSONBlock(grabbedText, "string", this)
                                    continue
                                }
                                return _singleItemList(JSONBlock(grabbedText, "string"))
                            }
                            return ValueType(ValueStore(grabbedText), "string")
                        } else {
                            grabbedText = ""
                        }
                    } else // used to copy values true, false, null and number
                    {
                        // ========== HANDLING GRABBING NUMBERS, BOOLEANS AND NULL
                        if (!isInQuotes && !isGrabbingText) {
                            val result = _getPrimitive(iterator, char)
                            if (result != null) {
                                if (processedPathIndex != paths.size) {
                                    if(restoreLastPointIfNeeded()) {
                                        continue
                                    }
                                    errorInfo = Pair(ErrorCode.nonNestedParent, processedPathIndex - 1)
                                    return null
                                }
                                if(grabAllPaths) {
                                    if(restoreLastPointIfNeeded()) {
                                        commonPathCollections += JSONBlock(result.second, result.first, this)
                                        continue
                                    }
                                    return _singleItemList(JSONBlock(result.second, result.first))
                                }
                                return ValueType(
                                    ValueStore(result.second),
                                    result.first
                                )
                            }
                        } else if (isGrabbingText) {
                            grabbedText += char.toInt().toChar()
                        }
                    }
                } else if (char == QUOTATION && !escapeCharacter) {
                    isInQuotes = !isInQuotes
                }
            } else // ========= SECTION RESPONSIBLE HANDLING OBJECT KEY
            {
                if (char == QUOTATION && !escapeCharacter) {
                    isInQuotes = !isInQuotes
                    // grabbing the matching correct object key as given in path
                    if ((advancedOffset + 1) == notationBalance || isNavigatingUnknownPath) {
                        isGrabbingKey = isInQuotes
                        if (isGrabbingKey) {
                            grabbingKey = byteArrayOf()
                        } else {
                            needProcessKey = true
                        }
                    }
                } else if (isGrabbingKey) {
                    if (lightMatch[lightMatch.size - (paths.size - processedPathIndex)]) {
                        when (char) {
                            in 48..57 -> {
                                grabbingKey += char
                            }
                            in 65..90 -> {
                                grabbingKey += (char + 32).toByte()
                            }
                            in 97..122 -> {
                                grabbingKey += char
                            }
                        }
                    } else {
                        grabbingKey += char
                    }
                } else if (needProcessKey && char == COLON) {
                    needProcessKey = false
                    // if found start searching for object value for object key
                    if (paths[processedPathIndex].contentEquals(grabbingKey)) {
                        processedPathIndex += 1
                        advancedOffset += 1
                        startSearchValue = true
                        if (isNavigatingUnknownPath) {
                            isNavigatingUnknownPath = false
                            advancedOffset = notationBalance
                        }
                    }
                }
            }
            // handling escape characters at the end ...
            if (escapeCharacter) {
                escapeCharacter = false
            } else if (char == ESCAPE) {
                escapeCharacter = true
            }
        }
        errorInfo = Pair(ErrorCode.other, processedPathIndex)
        return null
    }

    // iterators..

    internal fun _getStructuredData(iterator: ByteIterator, firstCharacter: Byte) : ValueType {
        val stack: MutableList<CollectionHolder> = mutableListOf()
        var isInQuotes = false
        var grabbedKey = ""
        var isGrabbingText = false
        var grabbedText = ""
        var notationBalance = 1
        var shouldProcessObjectValue = false
        var escapeCharacter = false
        stack += if (firstCharacter == OPEN_OBJECT) {
            CollectionHolder(isObject = true)
        } else {
            CollectionHolder(isObject = false)
        }

        while (iterator.hasNext()) {
            val char: Byte = iterator.nextByte()
            if (!isInQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                    if (stack.last().type == "object") {
                        stack.last().reservedObjectKey = grabbedKey
                    }
                    stack += CollectionHolder(isObject = char == OPEN_OBJECT)
                    shouldProcessObjectValue = false
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (isGrabbingText) {
                        if (stack.last().type == "object") {
                            stack.last().objectCollection[grabbedKey] = parseSingularValue(_trimSpace(grabbedText))
                        } else {
                            stack.last().arrayCollection += parseSingularValue(_trimSpace(grabbedText))
                        }
                        isGrabbingText = false
                    }
                    if (notationBalance == 0) {
                        return if (stack.first().type == "object") ValueType(
                            ValueStore(
                                parsedData = stack.last().objectCollection
                            ), "object"
                        ) else ValueType(
                            ValueStore(parsedData = stack.last().arrayCollection),
                            "array"
                        )
                    }
                    shouldProcessObjectValue = false
                    val child = stack.removeLast()
                    if (stack.last().type == "object") {
                        stack.last().assignChildToObject(child)
                    } else {
                        stack.last().appendChildToArray(child)
                    }
                } else if (char == COLON) {
                    shouldProcessObjectValue = true
                    grabbedKey = grabbedText
                }  else if (!isGrabbingText && ((char in 48..57) || char == MINUS || char == LETTER_T || char == LETTER_F || char == LETTER_N)) {
                    grabbedText = ""
                    isGrabbingText = true
                } else if (char == COMMA && isGrabbingText) {
                    isGrabbingText = false
                    if (stack.last().type == "object") {
                        stack.last().objectCollection[grabbedKey] = parseSingularValue(_trimSpace(grabbedText))
                    } else {
                        stack.last().arrayCollection += parseSingularValue(_trimSpace(grabbedText))
                    }
                    shouldProcessObjectValue = false
                }
            }
            if (!escapeCharacter && char == QUOTATION) {
                isInQuotes = !isInQuotes
                isGrabbingText = isInQuotes
                if (isGrabbingText) {
                    grabbedText = ""
                } else {
                    if (stack.last().type == "object") {
                        if (shouldProcessObjectValue) {
                            stack.last().objectCollection[grabbedKey] = grabbedText
                        }
                    } else {
                        stack.last().arrayCollection += grabbedText
                    }
                    shouldProcessObjectValue = false
                }
            } else if (isGrabbingText) {
                grabbedText += char.toInt().toChar()
            }
            if (escapeCharacter) {
                escapeCharacter = false
            } else if (char == ESCAPE) {
                escapeCharacter = true
            }
        }
        return ValueType(
            ValueStore(parsedData = byteArrayOf()),
            if (firstCharacter == OPEN_OBJECT) "object" else "array"
        )
    }

    private fun _iterateArrayWrite(iterator: ByteIterator, elementIndex: Int, copyingData: ByteWrapper) : Boolean {
        var notationBalance = 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        copyingData += OPEN_ARRAY
        if (elementIndex == 0) {
            return true
        }

        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!escapeCharacter && char == QUOTATION) {
                isQuotes = !isQuotes
            }
            if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (notationBalance == 0) {
                        return false
                    }
                } else if (char == COMMA && notationBalance == 1) {
                    cursorIndex += 1
                    if (cursorIndex == elementIndex) {
                        copyingData += char
                        return true
                    }
                }
            }
            if (escapeCharacter) {
                escapeCharacter = false
            } else if (char == ESCAPE) {
                escapeCharacter = true
            }
            copyingData += char
        }
        return false
    }

    private fun _addData(isInObject: Boolean, dataToAdd: Any, iterator: ByteIterator, copiedBytes: ByteWrapper, tabUnitCount: Int, paths: List<ByteArray>, isIntermediateAdd: Boolean = false) : Pair<ErrorCode, Int>? {
        if (!isIntermediateAdd && !_isLastCharacterOpenNode(copiedBytes)) {
            copiedBytes += COMMA
        }
        if (tabUnitCount != 0) {
            copiedBytes += NEW_LINE
            copiedBytes += fillTab((paths.size) * tabUnitCount)
        }
        if (isInObject) {
            copiedBytes += QUOTATION
            copiedBytes += paths[paths.size - 1]
            val endKeyPhrase: ByteArray = if (tabUnitCount == 0) byteArrayOf(QUOTATION,
                COLON
            ) else byteArrayOf(QUOTATION, COLON, TAB)
            copiedBytes += endKeyPhrase
        }
        var bytesToAdd =
            _serializeToBytes(dataToAdd, paths.size, tabUnitCount, QUOTATION)
        if (!isIntermediateAdd) {
            if (tabUnitCount != 0) {
                bytesToAdd += NEW_LINE
                bytesToAdd += fillTab((paths.size - 1) * tabUnitCount)
            }
            bytesToAdd += if (isInObject) CLOSE_OBJECT else CLOSE_ARRAY
        } else {
            // this was due to rare case when pushing to an empty array when push index is 0
            var trialBytes = byteArrayOf()
            while (iterator.hasNext()) {
                val char = iterator.nextByte()
                trialBytes += char
                if (char != TAB && char != NEW_LINE) {
                    if (char != CLOSE_ARRAY)
                        bytesToAdd += COMMA
                    else if (tabUnitCount != 0) {
                        bytesToAdd += NEW_LINE
                        bytesToAdd += fillTab((paths.size - 1) * tabUnitCount)
                    }
                    break
                }
            }
            bytesToAdd += trialBytes
        }
        _continueCopyData(iterator, copiedBytes, bytesToAdd, dataType = 4)
        return null
    }

    internal fun _write(path: String, data: Any, writeMode: UpdateMode) : Pair<ErrorCode, Int>? {
        if (contentType != "object" && contentType != "array") {
            return Pair(ErrorCode.nonNestableRootType, 0)
        }
        var tabUnitCount = 0
        if (jsonData[1] == NEW_LINE) {
            while ((tabUnitCount + 2) < jsonData.size) {
                if (jsonData[tabUnitCount + 2] == TAB) {
                    tabUnitCount += 1
                } else {
                    break
                }
            }
        }
        var isQuotes = false
        var isGrabbingKey = false
        var grabbedKey: ByteArray = byteArrayOf()
        var isEscaping = false
        var notationBalance = 0
        var processedindex = 0
        val paths: List<ByteArray> = _splitPath(path).first
        val copiedBytes = ByteWrapper(byteArrayOf())
        var searchValue = 0
        val iterator = jsonData.iterator()
        if (paths.isEmpty()) {
            return Pair(ErrorCode.emptyQueryPath, -1)
        }
        while (iterator.hasNext()) {
            val char = iterator.nextByte()

            if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                    if (searchValue == 1) {
                        if (writeMode == UpdateMode.onlyInsert) {
                            return Pair(ErrorCode.objectKeyAlreadyExists, processedindex - 1)
                        }
                        val bytesToAdd = _serializeToBytes(
                            data,
                            paths.size,
                            tabUnitCount,
                            QUOTATION
                        )
                        _continueCopyData(iterator, copiedBytes, bytesToAdd, dataType = 0)
                        return null
                    } else if (char == OPEN_ARRAY && (processedindex + 1) == notationBalance) {
                        val parsedInt = _toNumber(paths[processedindex]) ?: return Pair(ErrorCode.invalidArrayIndex, processedindex)
                        searchValue = 0
                        if (_iterateArrayWrite(iterator, elementIndex = parsedInt, copiedBytes)) {
                            processedindex += 1
                            if (processedindex == paths.size) {
                                searchValue = 1
                                if (writeMode == UpdateMode.delete) {
                                    _deleteData(iterator, copiedBytes, tabUnitCount, notationBalance, paths.size)
                                    return null
                                } else if (writeMode == UpdateMode.onlyInsert) {
                                    return _addData(false, data, iterator, copiedBytes, tabUnitCount, paths, isIntermediateAdd = true)
                                }
                            } else {
                                searchValue = 2
                            }
                        } else if (processedindex < paths.size - 1) {
                            return Pair(ErrorCode.arrayIndexNotFound, processedindex)
                        } else if (processedindex == (paths.size - 1)) {
                            return if (writeMode == UpdateMode.upsert || writeMode == UpdateMode.onlyInsert)
                                _addData(false, data, iterator, copiedBytes, tabUnitCount, paths)
                            else
                                Pair(ErrorCode.arrayIndexNotFound, processedindex)
                        }
                        continue
                    } else if (searchValue != 0) {
                        searchValue = 0
                    }
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (processedindex >= notationBalance) {
                        if (notationBalance + 1 == paths.size && (writeMode == UpdateMode.upsert || writeMode == UpdateMode.onlyInsert)) {
                            return _addData(char == CLOSE_OBJECT, data, iterator, copiedBytes, tabUnitCount, paths)
                        }
                        return Pair(if (char == CLOSE_OBJECT) ErrorCode.objectKeyNotFound else ErrorCode.arrayIndexNotFound, notationBalance)
                    }
                } else if (char == COLON && (processedindex + 1) == notationBalance) {
                    if (paths[processedindex].contentEquals(grabbedKey)) {
                        processedindex += 1
                        searchValue = 2
                        if (processedindex == paths.size) {
                            searchValue = 1
                            if (writeMode == UpdateMode.delete) {
                                _deleteData(iterator, copiedBytes, tabUnitCount, notationBalance, paths.size)
                                return null
                            }
                        }
                    }
                } else if (searchValue > 0 && ((char in 48..57) || char == MINUS || char == LETTER_T || char == LETTER_F || char == LETTER_N)) {
                    if (searchValue == 2) {
                        return Pair(ErrorCode.nonNestedParent, processedindex - 1)
                    }
                    if (writeMode == UpdateMode.onlyInsert) {
                        return Pair(ErrorCode.objectKeyAlreadyExists, processedindex - 1)
                    }
                    val bytesToAdd =
                        _serializeToBytes(data, paths.size, tabUnitCount, QUOTATION)
                    _continueCopyData(iterator, copiedBytes, bytesToAdd, dataType = 3)
                    return null
                }
            }
            if (!isEscaping && char == QUOTATION) {
                isQuotes = !isQuotes
                if (searchValue > 0) {
                    if (searchValue == 2) {
                        return Pair(ErrorCode.nonNestedParent, processedindex - 1)
                    }
                    if (writeMode == UpdateMode.onlyInsert) {
                        return Pair(ErrorCode.objectKeyAlreadyExists, processedindex - 1)
                    }
                    val bytesToAdd =
                        _serializeToBytes(data, paths.size, tabUnitCount, QUOTATION)
                    _continueCopyData(iterator, copiedBytes, bytesToAdd, dataType = 1)
                    return null
                } else if ((processedindex + 1) == notationBalance) {
                    isGrabbingKey = isQuotes
                    if (isGrabbingKey) {
                        grabbedKey = byteArrayOf()
                    }
                }
            } else if (isGrabbingKey) {
                grabbedKey += char
            }
            if (isEscaping) {
                isEscaping = false
            } else if (char == ESCAPE) {
                isEscaping = true
            }
            copiedBytes += char
        }
        return Pair(ErrorCode.other, processedindex)
    }
    
    private fun _iterateArray(iterator: ByteIterator, elementIndex: Int) : Boolean {
        var notationBalance = 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        if (elementIndex == 0) {
            return true
        }
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!escapeCharacter && char == QUOTATION) {
                isQuotes = !isQuotes
            }
            if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (notationBalance == 0) {
                        return false
                    }
                } else if (char == COMMA && notationBalance == 1) {
                    cursorIndex += 1
                    if (cursorIndex == elementIndex) {
                        return true
                    }
                }
            }
            if (escapeCharacter) {
                escapeCharacter = false
            } else if (char == ESCAPE) {
                escapeCharacter = true
            }
        }
        return false
    }

    private fun _grabData(copiedData: ByteWrapper, iterator: ByteIterator) {
        var notationBalance = 1
        var isQuotes = false
        var isEscape = false
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!isEscape && char == QUOTATION) {
                isQuotes = !isQuotes
            }
            if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (notationBalance == 0) {
                        copiedData += char
                        return
                    }
                }
                if (char > TAB) {
                    copiedData += char
                }
            } else {
                copiedData += char
            }
            if(isEscape) {
                isEscape = false
            } else if (char == ESCAPE) {
                isEscape = true
            }
        }
    }

    private fun _getObjectEntries(iterator: ByteIterator) : Array<JSONChild> {
        var values: Array<JSONChild> = arrayOf()
        var bytes: ByteWrapper
        var text = ""
        var dataType: String
        var isQuotes = false
        var grabbedKey = ""
        var isEscaping = false
        var shouldGrabItem = false
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!isEscaping && char == QUOTATION) {
                isQuotes = !isQuotes
                if (isQuotes) {
                    text = ""
                    continue
                } else {
                    if (shouldGrabItem) {
                        shouldGrabItem = false
                        values += JSONChild(this, text, "string").setKey(grabbedKey)
                    }
                }
            } else if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    bytes = ByteWrapper(byteArrayOf(char))
                    dataType = if (char == OPEN_OBJECT) "object" else "array"
                    _grabData(bytes, iterator)
                    values += JSONChild(this, bytes.bytes, dataType).setKey(grabbedKey)
                    shouldGrabItem = false
                    continue
                }
                if (shouldGrabItem) {
                    val result =  _getPrimitive(iterator, char)
                    if(result != null) {
                        values += JSONChild(this, result.second, result.first).setKey(grabbedKey)
                        shouldGrabItem = false
                        if(result.third) {
                            return values
                        }
                    }
                } else if (char == COLON) {
                    shouldGrabItem = true
                    grabbedKey = text
                    continue
                } else if (char == CLOSE_OBJECT) {
                    return values
                }
            } else {
                text += char.toInt().toChar()
            }
            if (isEscaping) {
                isEscaping = false
            } else if (char == ESCAPE) {
                isEscaping = true
            }
        }
        return values
    }

    private fun _getArrayValues(iterator: ByteIterator) : Array<JSONChild> {
        var values: Array<JSONChild> = arrayOf()
        var bytes: ByteWrapper
        var text = ""
        var dataType: String
        var isQuotes = false
        var isEscaping = false
        var index = 0
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!isEscaping && char == QUOTATION) {
                isQuotes = !isQuotes
                if (isQuotes) {
                    text = ""
                    continue
                } else {
                    values += JSONChild(this, text, "string").setIndex(index)
                    index += 1
                }
            } else if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    bytes = ByteWrapper(byteArrayOf(char))
                    dataType = if (char == OPEN_OBJECT) "object" else "array"
                    _grabData(bytes, iterator)
                    values += JSONChild(this, bytes.bytes, dataType).setIndex(index)
                    index += 1
                    continue
                }
                val result = _getPrimitive(iterator, char)
                if(result != null) {
                    values += JSONChild(this, result.second, result.first).setIndex(index)
                    index += 1
                    if(result.third) {
                        return values
                    }
                } else if (char == CLOSE_ARRAY) {
                    return values
                }
            } else {
                text += char.toInt().toChar()
            }
            if (isEscaping) {
                isEscaping = false
            } else if (char == ESCAPE) {
                isEscaping = true
            }
        }
        return values
    }

    private fun _isLastCharacterOpenNode(data: ByteWrapper) : Boolean {
        while (true) {
            if (data.last() == NEW_LINE || data.last() == TAB) {
                data.dropLast()
            } else {
                val last = data.last()
                return last == OPEN_OBJECT || last == OPEN_ARRAY
            }
        }
    }

    private fun _continueCopyData(iterator: ByteIterator, data: ByteWrapper, dataToAdd: ByteArray, dataType: Int) {
        var shouldRecoverComma = false
        // 0 - object/array, string - 1, others - 3
        if (dataType == 0) {
            var notationBalance = 1
            while (iterator.hasNext()) {
                val char = iterator.nextByte()
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                }
                if (notationBalance == 0) {
                    break
                }
            }
        } else if (dataType == 1) {
            while (iterator.hasNext()) {
                val char = iterator.nextByte()
                if (char == QUOTATION) {
                    break
                }
            }
        } else if (dataType == 3) {
            while (iterator.hasNext()) {
                val char = iterator.nextByte()
                if (char == COMMA) {
                    shouldRecoverComma = true
                    break
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    break
                }
            }
        }
        data += dataToAdd
        if (shouldRecoverComma) {
            data += COMMA
        }
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            data += char
        }
        jsonData = data.bytes
    }

    private fun _deleteData(iterator: ByteIterator, copiedData: ByteWrapper, tabUnitCount: Int, prevNotationBalance: Int, pathCount: Int) {
        var didRemovedFirstComma = false
        var isInQuotes = false
        var notationBalance = prevNotationBalance
        var escapeCharacter = false
        while (iterator.hasNext()) {
            val char = copiedData.last()

            if (!escapeCharacter && char == QUOTATION) {
                isInQuotes = !isInQuotes
            }
            if (!isInQuotes) {
                if ((char == OPEN_OBJECT || char == OPEN_ARRAY)) {
                    break
                } else if (char == COMMA) {
                    copiedData.dropLast()
                    didRemovedFirstComma = true
                    break
                }
            }
            copiedData.dropLast()
            if (escapeCharacter) {
                escapeCharacter = false
            } else if (char == ESCAPE) {
                escapeCharacter = true
            }
        }
        escapeCharacter = false
        isInQuotes = false
        while (iterator.hasNext()) {
            val char = iterator.nextByte()

            if (!escapeCharacter && char == QUOTATION) {
                isInQuotes = !isInQuotes
            }
            if (!isInQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (notationBalance == (pathCount - 1)) {
                        if (tabUnitCount != 0) {
                            if (didRemovedFirstComma) {
                                copiedData += NEW_LINE
                                copiedData += fillTab((pathCount - 1) * tabUnitCount)
                            }
                        }
                        copiedData += char
                        break
                    }
                }
            }
            if (char == COMMA && notationBalance == pathCount) {
                if (didRemovedFirstComma) {
                    copiedData += COMMA
                }
                break
            }
            if (escapeCharacter) {
                escapeCharacter = false
            } else if (char == ESCAPE) {
                escapeCharacter = true
            }
        }
        while (iterator.hasNext()) {
            val char = iterator.nextByte()

            copiedData += char
        }
        jsonData = copiedData.bytes
    }

    // utilities...

    private fun _asString(bytes: ByteArray) : String =
        bytes.decodeToString()

    private fun _toNumber(numBytes: ByteArray) : Int? {
        var copyBytes = numBytes
        var ans = 0
        var isNegative = false
        if (copyBytes.firstOrNull() == MINUS) {
            isNegative = true
            copyBytes = copyBytes.copyOfRange(1, copyBytes.size)
        }
        for (b in copyBytes) {
            if (b < 48 || b > 57) {
                return null
            }
            ans *= NEW_LINE
            ans += b - 48
        }
        if (isNegative) {
            ans *= -1
        }
        return ans
    }


    private fun _splitPath(path: String) : Pair<MutableList<ByteArray>, MutableList<Boolean>> {
        if(path.isBlank()) { return Pair(mutableListOf(), mutableListOf()) }
        val paths: MutableList<ByteArray> = mutableListOf()
        val lightSearch: MutableList<Boolean> = mutableListOf()
        val splitByte =  pathSplitter.code.toByte()
        var word: ByteArray = byteArrayOf()
        var repetitionCombo = 0

        for(char in path.toByteArray()) {
            if (char == splitByte) {
                if(word.isNotEmpty()) {
                    paths.add(word)
                    word = byteArrayOf()
                    lightSearch.add(repetitionCombo == 2)
                    repetitionCombo = 0
                }
                ++repetitionCombo
            } else {
                if(repetitionCombo == 2) {
                    if ((char in 97..122)
                        || (char in 48..57)
                    ) {
                        word += char
                    } else if (char in 65..90) {
                        word += (char + 32).toByte()
                    }
                } else {
                    word += char
                }
            }
        }

        lightSearch.add(repetitionCombo == 2)
        paths.add(word)

        if (pathSplitter != '.') {
            pathSplitter = '.'
        }
        return Pair(paths, lightSearch)
    }

    private fun parseSingularValue(input: String) : Any {
        return if (input.first() == 't') {
            true
        } else if (input.first() == 'f') {
            false
        } else if (input.first() == 'n') {
            Constants.NULL
        } else {
            input.toDoubleOrNull() ?: "#INVALID_NUMBER"
        }
    }

    private fun _getPrimitive(iterator: ByteIterator, firstCharacter: Byte) : Triple<String, String, Boolean>? {
        if (firstCharacter == LETTER_T) {
            return Triple("boolean", "true", false)
        } else if (firstCharacter == LETTER_F) {
            return Triple("boolean", "false", false)
        } else if (firstCharacter == LETTER_N) {
            return Triple("null", "null", false)
        } else if ((firstCharacter in 48 until COLON) || firstCharacter == MINUS) {
            var didContainerClosed = false
            var copiedNumber = "${firstCharacter.toInt().toChar()}"
            while (iterator.hasNext()) {
                val num = iterator.nextByte()
                if ((num in 48 until COLON) || num == DECIMAL) {
                    copiedNumber += num.toInt().toChar()
                } else {
                    if(num == CLOSE_ARRAY || num == CLOSE_OBJECT) {
                        didContainerClosed = true
                    }
                    break
                }
            }
            return Triple("number", copiedNumber, didContainerClosed)
        }
        return null
    }

    private fun _trimSpace(input: String) : String {
        var newString = input
        while ((newString.last().isWhitespace())) {
            newString = newString.dropLast(1)
        }
        return newString
    }
}