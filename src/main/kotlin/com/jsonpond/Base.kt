package com.jsonpond

internal class ByteWrapper(var bytes: ByteArray = byteArrayOf()) {
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
    var isBytes = false

    constructor(input: String) {
        string = input
    }

    constructor(text: String, data: ByteArray) {
        string = text
        bytes = data
        isBytes = data.isNotEmpty()
    }

    constructor(arrayData: Array<JSONBlock>) {
        array = arrayData
    }

    constructor(childData: Array<JSONChild>) {
        children = childData
    }

    constructor(data: ByteWrapper) {
        bytes = data.bytes
        isBytes = true
    }

    constructor(parsedData: Any) {
        tree = parsedData
    }
}

internal enum class UpdateMode {
    Upsert,
    OnlyUpdate,
    OnlyInsert,
    Delete
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
        private fun List<ByteArray>.joined(separator: ByteArray): ByteArray {
            var finalArray = byteArrayOf()
            if(isEmpty()) {
                return finalArray
            }
            for (index in 0 until this.lastIndex) {
                finalArray += this[index]
                finalArray += separator
            }
            finalArray += this.last()
            return finalArray
        }
        fun fillTab(repeatCount: Int) : ByteArray {
            val array = ByteArray(repeatCount)
            array.fill(TAB)
            return  array
        }
        internal fun serializeToBytes(node: Any?, index: Int, tabCount: Int, stringDelimiter: Byte) : ByteArray {
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
                                serializeToBytes(it.value, index + 1, tabCount, stringDelimiter)
                    }

                    if (tabCount != 0 && innerContent.isNotEmpty()) {
                        val spacer: ByteArray = fillTab((index + 1) * tabCount)
                        val endSpacer: ByteArray = fillTab(index * tabCount)
                        var data: ByteArray = byteArrayOf(OPEN_OBJECT, NEW_LINE)
                        val separator: ByteArray = byteArrayOf(COMMA, NEW_LINE) + spacer
                        data += spacer
                        data += innerContent.joined(separator)
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
                    val innerContent = node.map { serializeToBytes(it, index + 1, tabCount, stringDelimiter) }
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
                        ErrorCode.NonMatchingDataType,
                        (path?.split(pathSplitter)?.size ?: 0) - 1,
                        path ?: ""
                    )
                )
            }
            return null
        }
        return mapper(data)
    }

    internal fun prettifyContent(originalContent: ByteArray, tabSize: Int) : String {
        val iterator = PeekIterator(originalContent)
        var presentation = byteArrayOf()
        var notationBalance = 0
        var isEscaping = false
        var isQuotes = false

        if (originalContent[1] == NEW_LINE) {
            return originalContent.decodeToString() // already being pretty
        }


        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!isEscaping && char == quotation) {
                isQuotes = !isQuotes
            } else if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    if (iterator.hasNext()) {
                        val nextChar = iterator.nextByte()
                        if (nextChar == CLOSE_OBJECT || nextChar == CLOSE_ARRAY) {
                            presentation += char
                            presentation += nextChar
                            continue
                        }
                        iterator.moveBack()
                    }
                    notationBalance += 1
                    presentation += char
                    presentation += NEW_LINE
                    presentation += fillTab(notationBalance * tabSize)
                    continue
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    presentation += NEW_LINE
                    presentation += fillTab(notationBalance * tabSize)
                } else if (char == COMMA) {
                    presentation += char
                    presentation += NEW_LINE
                    presentation += fillTab(notationBalance * tabSize)
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
                quotation = if(char == '"')  34 else 39
                break
            }
        }
    }
    internal fun decodeData(
        inputPath: String,
        copyCollectionData: Boolean = false,
        grabAllPaths: Boolean = false,
        multiCollectionTypeConstraint: JSONType? = null
    ) : ValueType? {
        val results = exploreData(
            inputPath,
            copyCollectionData,
            grabAllPaths,
         multiCollectionTypeConstraint?.rawValue)
        errorInfo?.apply {
            errorHandler?.invoke(ErrorInfo(this.first, this.second, inputPath))
            errorHandler = null
        }
        return results
    }

    private fun singleItemList(source: JSONBlock): ValueType {
        return ValueType(ValueStore(arrayOf(source)), "CODE_ALL")
    }

    private fun exploreData(
        inputPath: String,
        copyCollectionData: Boolean,
        grabAllPaths: Boolean,
        multiCollectionTypeConstraint: String?
    ) : ValueType? {
        errorInfo = null
        if (!(contentType == "object" || contentType == "array")) {
            errorInfo = Pair(ErrorCode.NonNestableRootType, 0)
            return null
        }

        val (paths, lightMatch, arrayIndexes, searchDepths) = splitPath(inputPath)

        var processedPathIndex = 0
        var advancedOffset = 0
        val traversalHistory: MutableList<Pair<Int, Int>> = mutableListOf()
        var isInQuotes = false
        var startSearchValue = false
        var grabbingKey: ByteArray = byteArrayOf()
        var needProcessKey = false
        var isGrabbingKey = false
        var notationBalance = 0
        var searchDepth = 0
        var escapeCharacter = false
        var commonPathCollections: Array<JSONBlock> = arrayOf()

        var extractMode = 0

        if (grabAllPaths) extractMode = 2
        else if (copyCollectionData) extractMode = 1

        fun restoreLastPointIfNeeded(): Boolean {
            if (traversalHistory.isNotEmpty()){
                traversalHistory[traversalHistory.size - 1].apply {
                    processedPathIndex = this.first
                    advancedOffset = this.second
                }
                searchDepth = searchDepths[processedPathIndex]
                startSearchValue = false
                return true
            }
            return false
        }

        fun addToTraversalHistoryIfNeeded() {
            if (searchDepths[processedPathIndex] == 0) {
                traversalHistory += Pair(processedPathIndex, advancedOffset)
            }
            searchDepth = searchDepths[processedPathIndex]
        }

        if (paths.size == 0) {
            if(copyCollectionData) {
                val iterator = PeekIterator(jsonData)
                return getNextElement(iterator, true)
            }
            errorInfo = Pair(ErrorCode.EmptyQueryPath, -1)
            return null
        }

        if (paths.lastOrNull().contentEquals(intermediateSymbol)) {
            errorInfo = Pair(ErrorCode.CaptureUnknownElement, paths.size - 1)
            return null
        }

        val iterator = PeekIterator(jsonData)

        addToTraversalHistoryIfNeeded()

        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            // if within quotation ignore processing json literals...
            if (!isInQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1

                    // initiate elements counting inside array on reaching open bracket...
                    if (char == OPEN_ARRAY && (searchDepth == 0 || (advancedOffset + searchDepth) == notationBalance)) {
                        val parsedIndex = arrayIndexes[processedPathIndex]
                        // occur when trying to access element of array with non-number index
                        if (parsedIndex == null) {
                            if (restoreLastPointIfNeeded()) { continue }
                            errorInfo = Pair(ErrorCode.InvalidArrayIndex, processedPathIndex)
                            return null
                        }

                        if (processedPathIndex == (paths.size - 1)) {
                            val values = JSONBlockList()
                            val result = iterateArrayRecursive(iterator, parsedIndex, notationBalance, values, searchDepth == 0, extractMode, multiCollectionTypeConstraint)
                            if (result != null) {
                                return result
                            }
                            val isRestored = restoreLastPointIfNeeded()
                            if (values.data.isNotEmpty()) {
                                if (!isRestored) {
                                    return singleItemList(values.data[0])
                                }
                                commonPathCollections += values.data
                            }
                        } else if (iterateArray(iterator, parsedIndex)) {
                            processedPathIndex += 1
                            advancedOffset += searchDepth
                            if (searchDepth == 0) {
                                advancedOffset = notationBalance
                            }
                            startSearchValue = true
                            addToTraversalHistoryIfNeeded()
                        }
                    } else {
                        // move to next nest object and start looking attribute key on next nested object...
                        startSearchValue = false
                    }
                    continue
                }
                if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    // occur after all element in focused array or object is finished searching...
                    if (notationBalance == advancedOffset) {

                        // first - processedPathIndex
                        // second - advancedOffset
                        if (traversalHistory.isNotEmpty()) {
                            if (traversalHistory.last().second == advancedOffset) {
                                val lastIndex = traversalHistory.removeLast().first

                                if(traversalHistory.isEmpty()) {
                                    if (grabAllPaths) {
                                        return ValueType(
                                            ValueStore(
                                                commonPathCollections
                                            ), "CODE_ALL"
                                        )
                                    }
                                    errorInfo = Pair(ErrorCode.CannotFindElement, lastIndex)
                                    return null
                                }
                            }
                            traversalHistory.last().apply {
                                processedPathIndex = this.first
                                advancedOffset = this.second
                            }
                            searchDepth = searchDepths[processedPathIndex]
                            startSearchValue = false
                            continue
                        }
                        errorInfo = Pair(
                            if (arrayIndexes[processedPathIndex] == null)  ErrorCode.ObjectKeyNotFound else ErrorCode.ArrayIndexNotFound,
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
                    if (!escapeCharacter && char == quotation) {
                        isInQuotes = !isInQuotes
                        // if not the last processed value skip capturing value
                        if (processedPathIndex != paths.size) {
                            if(restoreLastPointIfNeeded()) {
                                continue
                            }
                            errorInfo = Pair(ErrorCode.NonNestedParent, processedPathIndex - 1)
                            return null
                        }
                    } else // used to copy values true, false, null and number
                    {
                        // ========== HANDLING GRABBING NUMBERS, BOOLEANS AND NULL
                        if (!isInQuotes) {
                            if ((char in 48..57) || char == MINUS
                                || char == LETTER_T || char == LETTER_F
                                || char == LETTER_N) {
                                if (processedPathIndex != paths.size) {
                                    if(restoreLastPointIfNeeded()) {
                                        continue
                                    }
                                    errorInfo = Pair(ErrorCode.NonNestedParent, processedPathIndex - 1)
                                    return null
                                }
                            }
                        }
                    }
                } else if (char == quotation && !escapeCharacter) {
                    isInQuotes = !isInQuotes
                }
            } else // ========= SECTION RESPONSIBLE HANDLING OBJECT KEY
            {
                if (char == quotation && !escapeCharacter) {
                    isInQuotes = !isInQuotes
                    // grabbing the matching correct object key as given in path
                    if (searchDepth == 0 || (advancedOffset + searchDepth) == notationBalance) {
                        isGrabbingKey = isInQuotes
                        if (isGrabbingKey) {
                            grabbingKey = byteArrayOf()
                        } else {
                            needProcessKey = true
                        }
                    }
                } else if (isGrabbingKey) {
                    if (lightMatch[processedPathIndex] != 1) {
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
                    if (isAttributeKeyMatch(lightMatch[processedPathIndex], grabbingKey, paths[processedPathIndex])
                            && arrayIndexes[processedPathIndex] == null) {
                        processedPathIndex += 1
                        advancedOffset += searchDepth
                        if (searchDepth == 0) {
                            advancedOffset = notationBalance
                        }
                        startSearchValue = true
                        if (processedPathIndex == paths.size) {
                            if (!grabAllPaths) {
                                return getNextElement(iterator, false)
                            }
                            val (value, type) = getNextElement(iterator, copyCollectionData)
                            val isRestored = restoreLastPointIfNeeded()
                            if (!(multiCollectionTypeConstraint == null || multiCollectionTypeConstraint != type))
                                continue
                            val elementToAdd: JSONBlock = if (value.isBytes) {
                                JSONBlock(value.bytes, type, this)
                            } else {
                                JSONBlock(value.string, type)
                            }
                            if (!isRestored) {
                                return singleItemList(elementToAdd)
                            }
                            commonPathCollections += elementToAdd
                        } else addToTraversalHistoryIfNeeded()
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
        errorInfo = Pair(ErrorCode.Other, processedPathIndex)
        return null
    }

    // iterators..

    internal fun getStructuredData(iterator: PeekIterator, firstCharacter: Byte) : ValueType {
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
                            stack.last().objectCollection[grabbedKey] = parseSingularValue(trimSpace(grabbedText))
                        } else {
                            stack.last().arrayCollection += parseSingularValue(trimSpace(grabbedText))
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
                        stack.last().objectCollection[grabbedKey] = parseSingularValue(trimSpace(grabbedText))
                    } else {
                        stack.last().arrayCollection += parseSingularValue(trimSpace(grabbedText))
                    }
                    shouldProcessObjectValue = false
                }
            }
            if (!escapeCharacter && char == quotation) {
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

    private fun iterateArrayWrite(iterator: PeekIterator, elementIndex: Int, copyingData: ByteWrapper) : Boolean {
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
            if (!escapeCharacter && char == quotation) {
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

    private fun addData(
        notationBalance: Int,
        isInObject: Boolean,
        dataToAdd: Any?,
        copiedBytes: ByteWrapper,
        tabUnitCount: Int,
        paths: List<ByteArray>,
        isIntermediateAdd: Boolean = false,
        isFirstValue: Boolean = false
    ) : Pair<ErrorCode, Int>? {
        if (!isIntermediateAdd) {
            copiedBytes.dropLast()
            if (!isLastCharacterOpenNode(copiedBytes)) {
                copiedBytes += 44
            }
        }
        if (tabUnitCount != 0 && !isFirstValue) {
            copiedBytes += NEW_LINE
            copiedBytes += fillTab(notationBalance * tabUnitCount)
        }
        if (isInObject) {
            copiedBytes += quotation
            copiedBytes += paths[paths.size - 1]
            val endKeyPhrase: ByteArray = if (tabUnitCount == 0) byteArrayOf(quotation,
                COLON
            ) else byteArrayOf(quotation, COLON, TAB)
            copiedBytes += endKeyPhrase
        }
        var bytesToAdd =
            serializeToBytes(dataToAdd, notationBalance, tabUnitCount, quotation)
        if (!isIntermediateAdd) {
            if (tabUnitCount != 0) {
                bytesToAdd += NEW_LINE
                bytesToAdd += fillTab((notationBalance - 1) * tabUnitCount)
            }
            bytesToAdd += if (isInObject) CLOSE_OBJECT else CLOSE_ARRAY
        } else {
            bytesToAdd += COMMA
            if (tabUnitCount != 0 && isFirstValue) {
                bytesToAdd += NEW_LINE
                bytesToAdd += fillTab(notationBalance * tabUnitCount)
            }
        }
        copiedBytes += bytesToAdd
        return null
    }

    internal fun write(inputPath: String, data:Any?, writeMode: UpdateMode, isMultiple: Boolean) {
        errorInfo = null
        if (!(contentType == "object" || contentType == "array")) {
            errorInfo = Pair(ErrorCode.NonNestableRootType, 0)
            return
        }

        var tabUnitCount = 0
        if (jsonData[1] == NEW_LINE) {
            while ((tabUnitCount + 2) < jsonData.size) {
                if (jsonData[tabUnitCount + 2] == TAB) {
                    tabUnitCount += 1
                } else { break }
            }
        }

        val (paths, lightMatch, arrayIndexes, searchDepths) = splitPath(inputPath)

        var processedPathIndex = 0
        var advancedOffset = 0
        val traversalHistory: MutableList<Pair<Int, Int>> = mutableListOf()

        var isInQuotes = false
        var startSearchValue = false
        var grabbingKey = byteArrayOf()
        val copiedBytes = ByteWrapper()
        var needProcessKey = false

        var isGrabbingKey = false
        var isObjectAttributeFound = false

        var notationBalance = 0
        var searchDepth = 1
        var escapeCharacter = false

        fun restoreLastPointIfNeeded(shouldRestore: Boolean = true): Boolean {
            if (shouldRestore && traversalHistory.size > 0) {
                traversalHistory[traversalHistory.size - 1].apply {
                    processedPathIndex = this.first
                    advancedOffset = this.second
                }
                startSearchValue = false
                searchDepth = searchDepths[processedPathIndex]
                return true
            }
            return false
        }

        fun isAttributeKeyMatch(lightMatch: Int, capturedKey: ByteArray, keyToMatch: ByteArray): Boolean {
            if (lightMatch < 3) {
                return capturedKey.contentEquals(keyToMatch)
            }
            var searchIndex = 0
            for (char in capturedKey) {
                if (char == keyToMatch[searchIndex]) {
                    searchIndex += 1
                    if (searchIndex == keyToMatch.size) {
                        return true
                    }
                }
            }
            return false
        }
        val iterator = PeekIterator(jsonData)

        fun finishWriting() {
            while (iterator.hasNext()) {
                val char = iterator.nextByte()
                copiedBytes += char
            }

            jsonData = copiedBytes.bytes
        }

        fun addToTraversalHistoryIfNeeded() {
            if (searchDepths[processedPathIndex] > -1) {
                traversalHistory += Pair(processedPathIndex, advancedOffset)
            }
            searchDepth = searchDepths[processedPathIndex]
        }

        if (paths.size == 0) {
            errorInfo = Pair(ErrorCode.EmptyQueryPath, -1)
            return
        }

        if (paths.lastOrNull().contentEquals(intermediateSymbol)) {
            errorInfo = Pair(ErrorCode.CaptureUnknownElement, paths.size - 1)
            return
        }

        addToTraversalHistoryIfNeeded()

        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            copiedBytes += char
            // if within quotation ignore processing json literals...
            if (!isInQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1

                    // initiate elements counting inside array on reaching open bracket...
                    if (char == OPEN_ARRAY && (searchDepth == 0 || (advancedOffset + searchDepth) == notationBalance)) {
                        val parsedIndex = arrayIndexes[processedPathIndex]
                        // occur when trying to access element of array with non-number index
                        if (parsedIndex == null) {
                            if (restoreLastPointIfNeeded()) {
                                continue
                            }
                            errorInfo = Pair(ErrorCode.InvalidArrayIndex, processedPathIndex)
                            return
                        }

                        if ((processedPathIndex + 1) == paths.size) {
                            if (iterateArrayWriteRecursive(iterator, parsedIndex, copiedBytes, notationBalance, searchDepth == 0, data, writeMode, isMultiple, tabUnitCount)) {
                                if (!restoreLastPointIfNeeded(isMultiple)) {
                                    finishWriting()
                                    return
                                }
                            }
                        } else {
                            if (iterateArrayWrite(iterator, parsedIndex, copiedBytes)) {
                                processedPathIndex += 1
                                advancedOffset += searchDepth
                                if (searchDepth == 0) {
                                    advancedOffset = notationBalance
                                }
                                startSearchValue = true
                                addToTraversalHistoryIfNeeded()
                            }
                        }
                    } else {
                        // move to next nest object and start looking attribute key on next nested object...
                        startSearchValue = false
                    }
                    continue
                }

                if (char ==  CLOSE_OBJECT || char ==  CLOSE_ARRAY) {
                    notationBalance -= 1
                    // section responsible for adding attribute at the end of the object if the attribute is not found
                    if ((searchDepth == 0 || notationBalance == advancedOffset) && char ==  CLOSE_OBJECT && (processedPathIndex + 1) == paths.size && (writeMode == UpdateMode.Upsert || writeMode == UpdateMode.OnlyInsert)) {
                        if (isObjectAttributeFound) {
                            isObjectAttributeFound = false
                        } else {
                            // make sure the the last attribute is an object attribute and not an array index
                            if (arrayIndexes[arrayIndexes.size - 1] == null) {
                                addData(notationBalance + 1, true, data, copiedBytes, tabUnitCount, paths)
                                if (!restoreLastPointIfNeeded(isMultiple)) {
                                    finishWriting()
                                    return
                                }
                            } else if (!restoreLastPointIfNeeded()) {
                                errorInfo = Pair(ErrorCode.ObjectKeyNotFound, paths.size - 1)
                                return
                            }
                        }
                    }

                    // occur after all element in focused array or object is finished searching...
                    if (notationBalance == advancedOffset) {
                        if (traversalHistory.size != 0) {
                            if (traversalHistory.last().second == advancedOffset) {
                                val lastIndex = traversalHistory.removeLast().first

                                if (traversalHistory.size == 0) {
                                    if (isMultiple) {
                                        finishWriting()
                                        return
                                    }
                                    errorInfo = Pair(ErrorCode.CannotFindElement, lastIndex)
                                    return
                                }
                            }
                            traversalHistory[traversalHistory.size - 1].apply {
                                processedPathIndex = this.first
                                advancedOffset = this.second
                            }
                            searchDepth = searchDepths[processedPathIndex]
                            startSearchValue = false
                            continue
                        }
                        // checking weather if currently the processing index is attribute or array index
                        errorInfo = Pair(if(arrayIndexes[processedPathIndex] == null) ErrorCode.ObjectKeyNotFound else ErrorCode.ArrayIndexNotFound, notationBalance)
                        return
                    }
                    continue
                }
            }

            // ======== FINISHED HANDLING JSON OPEN AND CLOSE NOTATION ==========
            if (startSearchValue) {
                if (notationBalance == advancedOffset) {
                    // ====== HANDLING GRABBING STRINGS =========
                    // ignore escaped double quotation characters inside string values...
                    if (!escapeCharacter && char == quotation) {
                        isInQuotes = !isInQuotes
                        // if not the last processed value skip capturing value
                        if (processedPathIndex != paths.size) {
                            if (restoreLastPointIfNeeded()) {
                                continue
                            }
                            errorInfo = Pair(ErrorCode.NonNestedParent, processedPathIndex - 1)
                            return
                        }
                        // used to copy values true, false, null and number
                    } else {
                        // ========== HANDLING GRABBING NUMBERS, Booleans AND NULL
                        if (!isInQuotes && (char in 48..57) || char == MINUS
                            || char == LETTER_T || char == LETTER_F
                            || char == LETTER_N
                        ) {
                            if (processedPathIndex != paths.size) {
                                if (restoreLastPointIfNeeded()) {
                                    continue
                                }
                                errorInfo = Pair(ErrorCode.NonNestedParent, processedPathIndex - 1)
                                return
                            }
                        }
                    }
                } else if (char == quotation && !escapeCharacter) {
                    isInQuotes = !isInQuotes
                }

                // ========= SECTION RESPONSIBLE HANDLING OBJECT KEY
            } else {
                if (char == quotation && !escapeCharacter) {
                    isInQuotes = !isInQuotes
                    // grabbing the matching correct object key as given in path
                    if (searchDepth == 0 || (advancedOffset + 1) == notationBalance) {
                        isGrabbingKey = isInQuotes
                        if (isGrabbingKey) {
                            grabbingKey = byteArrayOf()
                        } else {
                            needProcessKey = true
                        }
                    }
                } else if (isGrabbingKey) {
                    // section for accumulating characters for attribute key when light search is active
                    if (lightMatch[processedPathIndex] != 1) {
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
                    if (isAttributeKeyMatch(lightMatch[processedPathIndex], grabbingKey, paths[processedPathIndex]) && arrayIndexes[processedPathIndex] == null) {
                        processedPathIndex += 1
                        advancedOffset += searchDepth
                        if (searchDepth == 0) {
                            advancedOffset = notationBalance
                        }
                        startSearchValue = true

                        // section responsible to when last attribute is found
                        if(processedPathIndex == paths.size) {
                            if (writeMode == UpdateMode.Delete) {
                                deleteData(iterator, copiedBytes, tabUnitCount, notationBalance)
                                if (restoreLastPointIfNeeded(isMultiple)) { continue } else {
                                    finishWriting()
                                    return
                                }
                            } else if (writeMode == UpdateMode.OnlyInsert) {
                                if (restoreLastPointIfNeeded()) {
                                    isObjectAttributeFound = true
                                    continue
                                }
                                errorInfo = Pair(ErrorCode.ObjectKeyAlreadyExists, processedPathIndex - 1)
                                return
                            } else {
                                val bytesToAdd = serializeToBytes(data, notationBalance, tabUnitCount, quotation)
                                replaceData(iterator, bytesToAdd, copiedBytes)
                                if (writeMode == UpdateMode.Upsert) {
                                    isObjectAttributeFound = true
                                }
                                if (restoreLastPointIfNeeded(isMultiple)) { continue } else {
                                    finishWriting()
                                    return
                                }
                            }
                        } else addToTraversalHistoryIfNeeded()
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

        errorInfo = Pair(ErrorCode.Other, processedPathIndex)
        return
    }

    private fun iterateArray(iterator: PeekIterator, elementIndex: Int) : Boolean {
        var notationBalance = 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        if (elementIndex == 0) {

            while (iterator.hasNext()) {
                val char = iterator.nextByte()
                if (!(char == NEW_LINE || char == TAB)) {
                    iterator.moveBack()
                    if (char == CLOSE_ARRAY) {
                        return false
                    }
                    return true
                }
            }
            return false
        }

        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!escapeCharacter && char == quotation) {
                isQuotes = !isQuotes
            }
            if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (notationBalance == 0) {
                        iterator.moveBack()
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

    private fun getNextElement(iterator: PeekIterator, isCopyCollection: Boolean): ValueType {
        var text = ""
        val data = ByteWrapper()
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (char == quotation) {
                var isEscape = false
                while (iterator.hasNext()) {
                    val stringChar = iterator.nextByte()
                    if (!isEscape && stringChar == quotation) {
                        return ValueType(ValueStore(text), "string")
                    }
                    if (isEscape) {
                        isEscape = false
                    } else if (stringChar == ESCAPE) {
                        isEscape = true
                    }
                    text += stringChar.toInt().toChar()
                }
            } else if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                if(extractInnerContent) return getStructuredData(iterator, char)
                if (isCopyCollection) {
                    return if (char == OPEN_OBJECT) {
                        ValueType(ValueStore(childData = getObjectEntries(iterator)), "CODE_COLLECTION")
                    } else {
                        ValueType(ValueStore(childData = getArrayValues(iterator)), "CODE_COLLECTION")
                    }
                }
                data += char
                grabData(data, iterator)
                return ValueType(ValueStore(data), if(char == OPEN_OBJECT) "object" else "array")
            } else {
                val result = getPrimitive(iterator, char)
                if (result != null) {
                    return ValueType(ValueStore(result.second), result.first)
                }
            }
        }
        return ValueType(ValueStore("not data to retrieve"), "string")
    }

    data class JSONBlockList(@Suppress("ArrayInDataClass") var data: Array<JSONBlock> = arrayOf()) {
        operator fun plusAssign(block: JSONBlock) {
             data = data.plus(block)
        }
    }

    private fun iterateArrayRecursive(iterator: PeekIterator, elementIndex: Int, initialNotationBalance: Int, values: JSONBlockList, shouldRecurse: Boolean, mode: Int, typeConstraint: String?): ValueType? {
        var notationBalance = initialNotationBalance
        val stopBalance = initialNotationBalance - 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        var innerItem: ValueType?

        if (elementIndex == 0) {
            while (iterator.hasNext()) {
                val char = iterator.nextByte()

                if (!(char == NEW_LINE || char == TAB)) {
                    iterator.moveBack()
                    if (char == CLOSE_ARRAY) {
                        return null
                    }
                    val result = getNextElement(iterator, mode == 1)
                    if (mode < 2) return result
                    if (typeConstraint == null || typeConstraint == result.type) {
                        values += if (result.value.isBytes) {
                            JSONBlock(result.value.bytes, result.type, this)
                        } else {
                            JSONBlock(result.value.string, result.type)
                        }
                        return null
                    }
                }
            }
            return null
        }

        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!escapeCharacter && char == quotation) {
                isQuotes = !isQuotes
            }
            if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                    if (char == OPEN_ARRAY && shouldRecurse) {
                        innerItem = iterateArrayRecursive(iterator, elementIndex, initialNotationBalance, values, true, mode, typeConstraint)
                        // if innerItem is null then it means this is a multiple data read
                        if (innerItem != null) {
                            return innerItem
                        }
                    }
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (notationBalance == stopBalance) {
                        iterator.moveBack()
                        return null
                    }
                } else if (char == COMMA && notationBalance == initialNotationBalance) {
                    cursorIndex += 1
                    if (cursorIndex == elementIndex) {
                        val result = getNextElement(iterator, mode == 1)
                        if (mode < 2) return result
                        if (typeConstraint == null || typeConstraint == result.type) {
                            values += if (result.value.isBytes) {
                                JSONBlock(result.value.bytes, result.type, this)
                            } else {
                                JSONBlock(result.value.string, result.type)
                            }
                            return null
                        }
                    }
                }
            }

            if (escapeCharacter) {
                escapeCharacter = false
            } else if (char == ESCAPE) {
                escapeCharacter = true
            }
        }
        return null
    }
    
    private fun iterateArrayWriteRecursive(iterator: PeekIterator, elementIndex: Int, copyingData: ByteWrapper, initialNotationBalance: Int, shouldRecurse: Boolean, dataToAdd: Any?, updateMode: UpdateMode, isMultiple: Boolean, tabUnitCount: Int): Boolean {
        var notationBalance = initialNotationBalance
        val stopBalance = initialNotationBalance - 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        var didProcessed = false

        if (elementIndex == 0) {
            while (iterator.hasNext()) {
                val char = iterator.nextByte()

                if (!(char == NEW_LINE || char == TAB)) {
                    iterator.moveBack()
                    if (char == CLOSE_ARRAY) {
                        copyingData += char
                        if (updateMode == UpdateMode.OnlyInsert || updateMode == UpdateMode.Upsert) {
                            addData(notationBalance, false, dataToAdd, copyingData, tabUnitCount, mutableListOf())
                            copyingData.dropLast()
                            return true
                        }
                        copyingData.dropLast()
                        return false
                    }
                    when (updateMode) {
                        UpdateMode.Delete -> {
                            deleteData(iterator, copyingData, tabUnitCount, notationBalance)
                        }
                        UpdateMode.OnlyInsert -> {
                            addData(notationBalance, false, dataToAdd, copyingData, tabUnitCount, mutableListOf(), isIntermediateAdd = true, isFirstValue = true)
                        }
                        else -> {
                            val replacingData = serializeToBytes(dataToAdd, notationBalance, tabUnitCount, quotation)
                            replaceData(iterator, replacingData, copyingData)
                        }
                    }
                    return true
                }
                copyingData += char
            }
            return false
        }

        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            copyingData += char
            if (!escapeCharacter && char == quotation) {
                isQuotes = !isQuotes
            }
            if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                    if (char == OPEN_ARRAY && shouldRecurse) {
                        didProcessed = iterateArrayWriteRecursive(iterator, elementIndex, copyingData, notationBalance, true, dataToAdd, updateMode, isMultiple, tabUnitCount)
                        if (!isMultiple && didProcessed) {
                            return true
                        }
                    }
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (notationBalance == stopBalance) {
                        iterator.moveBack()
                        if (updateMode == UpdateMode.OnlyInsert || updateMode == UpdateMode.Upsert) {
                            addData(notationBalance + 1, false, dataToAdd, copyingData, tabUnitCount, mutableListOf())
                            copyingData.dropLast()
                            return true
                        }
                        copyingData.dropLast()
                        return didProcessed
                    }
                } else if (char == COMMA && notationBalance == initialNotationBalance) {
                    cursorIndex += 1
                    if (cursorIndex == elementIndex) {
                        when (updateMode) {
                            UpdateMode.Delete -> {
                                deleteData(iterator, copyingData, tabUnitCount, notationBalance)
                            }
                            UpdateMode.OnlyInsert -> {
                                addData(notationBalance, false, dataToAdd, copyingData, tabUnitCount, mutableListOf(), isIntermediateAdd = true)
                            }
                            else -> {
                                val replacingData = serializeToBytes(dataToAdd, notationBalance, tabUnitCount, quotation)
                                replaceData(iterator, replacingData, copyingData)
                            }
                        }
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


    private fun grabData(copiedData: ByteWrapper, iterator: PeekIterator) {
        var notationBalance = 1
        var isQuotes = false
        var isEscape = false
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!isEscape && char == quotation) {
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

    private fun getObjectEntries(iterator: PeekIterator) : Array<JSONChild> {
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
            if (!isEscaping && char == quotation) {
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
                    grabData(bytes, iterator)
                    values += JSONChild(this, bytes.bytes, dataType).setKey(grabbedKey)
                    shouldGrabItem = false
                    continue
                }
                if (shouldGrabItem) {
                    val result =  getPrimitive(iterator, char)
                    if(result != null) {
                        values += JSONChild(this, result.second, result.first).setKey(grabbedKey)
                        shouldGrabItem = false
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

    private fun getArrayValues(iterator: PeekIterator) : Array<JSONChild> {
        var values: Array<JSONChild> = arrayOf()
        var bytes: ByteWrapper
        var text = ""
        var dataType: String
        var isQuotes = false
        var isEscaping = false
        var index = 0
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!isEscaping && char == quotation) {
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
                    grabData(bytes, iterator)
                    values += JSONChild(this, bytes.bytes, dataType).setIndex(index)
                    index += 1
                    continue
                }
                val result = getPrimitive(iterator, char)
                if(result != null) {
                    values += JSONChild(this, result.second, result.first).setIndex(index)
                    index += 1
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

    private fun isLastCharacterOpenNode(data: ByteWrapper) : Boolean {
        while (true) {
            if (data.last() == NEW_LINE || data.last() == TAB) {
                data.dropLast()
            } else {
                val last = data.last()
                return last == OPEN_OBJECT || last == OPEN_ARRAY
            }
        }
    }

    private fun replaceData(iterator: PeekIterator, dataToAdd: ByteArray, copiedBytes: ByteWrapper) {

        // 0 - object/array, string - 1, others - 3
        var notationBalance = 0
        var type = -1
        var isInQuotes = false
        var isEscaping = false

        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                type = 1
                notationBalance = 1
                break
            }
            if (char == quotation) {
                type = 2
                isInQuotes = true
                break
            }
            if ((char in 48..57) || char == MINUS || (char in 97..122)) {
                type = 3
                break
            }
            copiedBytes += char
        }

        if (type == 1 || type == 2) {
            while (iterator.hasNext()) {
                val char = iterator.nextByte()
                if (isInQuotes) {
                    if (!isEscaping && char == quotation) {
                        if (type == 2) {
                            copiedBytes += dataToAdd
                            return
                        }
                        isInQuotes = false

                    } else if (isEscaping) {
                        isEscaping = false
                    } else if (char == ESCAPE) {
                        isEscaping = true
                    }
                } else {
                    if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                        notationBalance += 1
                    } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                        notationBalance -= 1
                        if (notationBalance == 0) {
                            copiedBytes += dataToAdd
                            return
                        }
                    } else if (char == quotation) {
                        isInQuotes = true
                    }
                }

            }
        } else if (type == 3) {
            while (iterator.hasNext()) {
                val char = iterator.nextByte()
                if (!(isNumber(char) || (char in 97..122))) {
                    copiedBytes += dataToAdd
                    iterator.moveBack()
                    return
                }
            }
        }
    }

    private fun isNumber(char: Byte): Boolean {
        return (char in 48..57) || char == DECIMAL || char == MINUS
    }

    private fun deleteData(iterator: PeekIterator, copiedData: ByteWrapper, tabUnitCount: Int, prevNotationBalance: Int) {
        var didRemovedFirstComma = false
        var isInQuotes = false
        var notationBalance = prevNotationBalance
        var escapeCharacter = false
        while (iterator.hasNext()) {
            val char = copiedData.last()

            if (!escapeCharacter && char == quotation) {
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

            if (!escapeCharacter && char == quotation) {
                isInQuotes = !isInQuotes
            }
            if (!isInQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (notationBalance == (prevNotationBalance - 1)) {
                        if (tabUnitCount != 0) {
                            if (didRemovedFirstComma) {
                                copiedData += NEW_LINE
                                copiedData += fillTab((prevNotationBalance - 1) * tabUnitCount)
                            }
                        }
                        iterator.moveBack()
                        return
                    }
                } else if (char == COMMA && notationBalance == prevNotationBalance) {
                    if (didRemovedFirstComma) {
                        copiedData += COMMA
                    }
                    return
                }
            }

            if (escapeCharacter) {
                escapeCharacter = false
            } else if (char == ESCAPE) {
                escapeCharacter = true
            }
        }
    }

    // utilities...

    @Suppress("unused")
    private fun asString(bytes: ByteArray) : String =
        bytes.decodeToString()


    private fun getIntermediateSymbolDepthLimit(word: ByteArray) : Int? {
        var matchIndex = 0
        var stage = 0
        var index = 0
        for (char in word) {
            if (stage == 0 && char == intermediateSymbol[matchIndex]) {
                matchIndex += 1
                if (matchIndex == intermediateSymbol.size) {
                    stage = 1
                }
            } else if (stage == 1 && char == OPEN_OBJECT) {
                stage = 2
            } else if (stage > 1 && (char in 48..57)) {
                index = (index * 10) + (char - 48)
                stage = 3
            } else if (stage == 3 && char == CLOSE_OBJECT) {
                return if(index == 0) 1 else index
            } else {
                return null
            }

        }

        if (stage == 1) {
            return 0
        }
        return null
    }

    data class SplitPathData(
        val paths: MutableList<ByteArray>,
        val lightMatch: MutableList<Int>,
        val arrayIndexes: MutableList<Int?>,
        val searchDepths: MutableList<Int>
    )

    private fun splitPath(path: String) : SplitPathData {
        if(path.isBlank()) { return SplitPathData(mutableListOf(), mutableListOf(), mutableListOf(), mutableListOf()) }
        val paths: MutableList<ByteArray> = mutableListOf()
        val arrayIndexes: MutableList<Int?> = mutableListOf()
        val lightMatch: MutableList<Int> = mutableListOf()
        val searchDepths: MutableList<Int> = mutableListOf()
        var arrayIndex = 0
        var isNumber = true
        var numberSign = 1
        var assignedDepth = 1
        val splitByte =  pathSplitter.code.toByte()
        var word: ByteArray = byteArrayOf()
        var repetitionCombo = 1

        for (char in path.toByteArray()) {
            if (char == splitByte) {
                if (word.isNotEmpty()) {
                    val depth = getIntermediateSymbolDepthLimit(word)
                    assignedDepth = if (depth != null) {
                        depth
                    } else {
                        arrayIndexes.add(if(isNumber) arrayIndex * numberSign else null)
                        lightMatch.add(repetitionCombo)
                        paths.add(word)
                        searchDepths.add(assignedDepth)
                        1
                    }
                    word = byteArrayOf()
                    isNumber = true
                    numberSign = 1
                    arrayIndex = 0
                    repetitionCombo = 0
                }
                repetitionCombo += 1
            } else {
                if (repetitionCombo == 1) {
                    if (char in 48..57) {
                        if (isNumber) {
                            arrayIndex = (arrayIndex * 10) + (char - 48)
                        }
                    } else if (isNumber && char == MINUS) {
                        numberSign = if(numberSign == 1) -1 else 1
                    } else {
                        isNumber = false
                    }
                    word += char
                } else {
                    isNumber = false
                    if ((char in 97..122) || (char in 48..57)) {
                        word += char
                    }  else if (char in 65..90) {
                        word += (char + 32).toByte()
                    }
                }
            }
        }

        arrayIndexes.add(if (isNumber) arrayIndex * numberSign else null)
        lightMatch.add(repetitionCombo)
        paths.add(word)
        val lastDepth = getIntermediateSymbolDepthLimit(word)
        if (lastDepth == null) {
            searchDepths.add(assignedDepth)
        } else {
            paths.add(intermediateSymbol)
        }

        if (pathSplitter != '.') {
            pathSplitter = '.'
        }

        return SplitPathData(paths, lightMatch, arrayIndexes, searchDepths)
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

    private fun getPrimitive(iterator: PeekIterator, firstCharacter: Byte) : Pair<String, String>? {
        if (firstCharacter == LETTER_T) {
            return Pair("boolean", "true")
        } else if (firstCharacter == LETTER_F) {
            return Pair("boolean", "false")
        } else if (firstCharacter == LETTER_N) {
            return Pair("null", "null")
        } else if ((firstCharacter in 48 until 58) || firstCharacter == MINUS) {
            var copiedNumber = "${firstCharacter.toInt().toChar()}"
            while (iterator.hasNext()) {
                val num = iterator.nextByte()
                if ((num in 48 until 58) || num == DECIMAL) {
                    copiedNumber += num.toInt().toChar()
                } else {
                    if(num == CLOSE_ARRAY || num == CLOSE_OBJECT) {
                        iterator.moveBack()
                    }
                    break
                }
            }
            return Pair("number", copiedNumber)
        }
        return null
    }

    private fun isAttributeKeyMatch(lightMatch: Int, capturedKey: ByteArray, keyToMatch: ByteArray): Boolean {
        if (lightMatch < 3) {
            return capturedKey.contentEquals(keyToMatch)
        }
        var searchIndex = 0
        for (char in capturedKey) {
            if (char == keyToMatch[searchIndex]) {
                searchIndex += 1
                if (searchIndex == keyToMatch.size) {
                    return true
                }
            }
        }
        return false
    }

    private fun trimSpace(input: String) : String {
        var newString = input
        while ((newString.last().isWhitespace())) {
            newString = newString.dropLast(1)
        }
        return newString
    }
}
