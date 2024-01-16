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

internal class TypeConstraint(
    private val requiredType: String? = null,
    private val canStringParse: Boolean = false
) {

    fun isTypeMatch(type: String): Boolean {
        return requiredType == null
                || requiredType == type
                || (canStringParse && type == "string")
    }
}

internal data class ValueType(val value: ValueStore, val type: String)
internal class ValueStore {
    var string: String = ""
    var bytes: ByteArray = byteArrayOf()
    var array: Array<JSONBlock> = arrayOf()
    var children = JSONCollection()
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

    constructor(childData: JSONCollection) {
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

internal open class Base: State() {
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

        internal fun serializeToBytes(node: Any?, stringDelimiter: Byte) : ByteArray {
            when (node) {
                is Map<*, *> -> {
                    val innerContent: List<ByteArray> = node.map {
                        byteArrayOf(stringDelimiter) +
                                it.key.toString().toByteArray() +
                                byteArrayOf(
                                    stringDelimiter, COLON
                                ) +
                                serializeToBytes(it.value, stringDelimiter)
                    }

                    return (byteArrayOf(OPEN_OBJECT) + (innerContent.joined(byteArrayOf(
                        COMMA
                    )))) + byteArrayOf(CLOSE_OBJECT)
                }
                is List<*> -> {
                    val innerContent = node.map { serializeToBytes(it, stringDelimiter) }

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
                is JSONBlock -> {
                    return node.base.jsonData
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
        if (path != null) {
            val result = decodeData(path, typeConstraint =  TypeConstraint(fieldName, ignoreType))
            return if (result == null) null
            else {
                return mapper(result.value)
            }
        }

        if (TypeConstraint(fieldName, ignoreType).isTypeMatch(contentType)) {
            return mapper(ValueStore(jsonText, jsonData))
        }
        if (errorHandler != null) {
            errorHandler?.invoke(ErrorInfo(ErrorCode.NonMatchingDataType, -1, ""))
            errorHandler = null
        }
        return null
    }

    internal fun prettifyContent(originalContent: ByteArray, tabSize: Int) : String {
        val iterator = PeekIterator(originalContent)
        var presentation = byteArrayOf()
        var notationBalance = 0
        var isEscaping = false
        var isQuotes = false

        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!isEscaping && char == quotation) {
                isQuotes = !isQuotes
            } else if (!isQuotes) {
                if (char == TAB || char == NEW_LINE) {
                    continue
                } else if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
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
        return asString(presentation)
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
        typeConstraint: TypeConstraint = TypeConstraint()
    ) : ValueType? {
        val results = exploreData(
            inputPath,
            copyCollectionData,
            grabAllPaths,
            typeConstraint)
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
        typeConstraint: TypeConstraint
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
                            val result = iterateArrayRecursive(iterator, parsedIndex, notationBalance, values, searchDepth == 0, extractMode, typeConstraint)
                            if (extractMode < 2) {
                                if (result == null) {
                                    if (restoreLastPointIfNeeded()) { continue }
                                    errorInfo = Pair(ErrorCode.ArrayIndexNotFound, processedPathIndex)
                                    return null
                                }
                                return result
                            }
                            if (values.data.isNotEmpty()) {
                                if (!restoreLastPointIfNeeded()) {
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
            else {
                // handling escape characters at the end ...
                if (escapeCharacter) {
                    escapeCharacter = false
                } else if (char == ESCAPE) {
                    escapeCharacter = true
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
                            val capturedElement = getNextElement(iterator, copyCollectionData)
                            val isRestored = restoreLastPointIfNeeded()

                            if (!grabAllPaths) {
                                if (typeConstraint.isTypeMatch(capturedElement.type)) {
                                    return capturedElement
                                }
                                if (isRestored) { continue }
                                errorInfo = Pair(ErrorCode.ObjectKeyNotFound, processedPathIndex - 1)
                                return null
                            }
                            if (!typeConstraint.isTypeMatch(capturedElement.type)) { continue }

                            val elementToAdd: JSONBlock = if (capturedElement.value.isBytes) {
                                JSONBlock(capturedElement.value.bytes, capturedElement.type, this)
                            } else {
                                JSONBlock(capturedElement.value.string, capturedElement.type)
                            }
                            if (!isRestored) {
                                return singleItemList(elementToAdd)
                            }
                            commonPathCollections += elementToAdd
                        } else addToTraversalHistoryIfNeeded()
                    }
                }
            }
        }
        errorInfo = Pair(ErrorCode.Other, processedPathIndex)
        return null
    }

    private fun parseSingularValue(input: String): Any? {
        if (input[0] == 't') {
            return true
        } else if (input[0] == 'f') {
            return false
        } else if (input[0] == 'n') {
            return null
        } else {
            return input.toDoubleOrNull() ?: return "#INVALID_NUMERIC"
        }
    }

    // iterators..

    private fun parseNextElement(iterator: PeekIterator, firstCharacter: Byte): Any {
        var isEscaping = false
        val objectValue: MutableMap<String, Any?> = mutableMapOf()
        val arrayValue: MutableList<Any?> = mutableListOf()
        var grabbedKey = ""
        var grabbedText = ""
        val isObject = firstCharacter == OPEN_OBJECT
        var isKeyCaptured = false
        var isInQuotes = false
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!isEscaping && char == quotation) {
                isInQuotes = !isInQuotes
                if (isInQuotes) {
                    // inside a array no need to worry about keys...
                    grabbedText = ""
                } else {
                    if (isObject) {
                        if (isKeyCaptured) {
                            objectValue[grabbedKey] = grabbedText
                            isKeyCaptured = false
                        } else {
                            grabbedKey = grabbedText
                            isKeyCaptured = true
                        }
                    } else {
                        arrayValue += grabbedText
                    }
                }
            } else if (isInQuotes) {
                if (isEscaping) {
                    isEscaping = false
                } else if (char == ESCAPE) {
                    isEscaping = true
                }
                grabbedText += char.toInt().toChar()
            } else {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    if (isObject) {
                        objectValue[grabbedKey] = parseNextElement(iterator, char)
                        isKeyCaptured = false
                    } else {
                        arrayValue.add(parseNextElement(iterator, char))
                    }
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY ){
                    if (isObject) { return objectValue }
                    return arrayValue
                } else {
                    val value = getPrimitive(iterator, char)?.second ?: continue
                    if (isObject) {
                        objectValue[grabbedKey] = parseSingularValue(value)
                        isKeyCaptured = false
                    } else {
                        arrayValue.add(parseSingularValue(value))
                    }
                }
            }

        }
        return "#INVALID_TYPE"
    }

    internal fun getStructuredData(iterator: PeekIterator, firstCharacter: Byte): ValueType{
        val dataType = if (firstCharacter == OPEN_OBJECT) "object" else "array"
        return ValueType(
                ValueStore(
                parseNextElement(iterator, firstCharacter)
        ), dataType)
    }

    private fun iterateArrayWrite(iterator: PeekIterator, elementIndex: Int, copyingData: ByteWrapper) : Boolean {
        var notationBalance = 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        copyingData += OPEN_ARRAY
        if (elementIndex == 0) {
            val nextChar = iterator.peek() ?: return false
            return nextChar != CLOSE_ARRAY
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
        isInObject: Boolean,
        data: ByteArray,
        copiedBytes: ByteWrapper,
        paths: List<ByteArray>,
        isIntermediateAdd: Boolean = false,
    ) : Pair<ErrorCode, Int>? {
        if (!isIntermediateAdd) {
            copiedBytes.dropLast()
            if (!(copiedBytes.last() == OPEN_OBJECT || copiedBytes.last() == OPEN_ARRAY)) {
                copiedBytes += COMMA
            }
        }

        if (isInObject) {
            copiedBytes += quotation
            copiedBytes += paths[paths.size - 1]
            copiedBytes += byteArrayOf(quotation, COLON)
        }

        copiedBytes += data
        copiedBytes += if (isIntermediateAdd) COMMA
        else if (isInObject) CLOSE_OBJECT else CLOSE_ARRAY
        return null
    }

    internal fun handleWrite(path: String, data: Any?, mode: UpdateMode, multiple: Boolean) {
        write(path, serializeToBytes(data, quotation), mode, multiple)
        errorInfo?.apply {
            errorHandler?.invoke(ErrorInfo(this.first, this.second, path))
            errorHandler = null
        }
    }

    private fun write(inputPath: String, data:ByteArray, writeMode: UpdateMode, isMultiple: Boolean) {
        errorInfo = null
        if (!(contentType == "object" || contentType == "array")) {
            errorInfo = Pair(ErrorCode.NonNestableRootType, 0)
            return
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
            val char = iterator.nextByte()
            if (isInQuotes || char > TAB) {
                copiedBytes += char
            }
            if (!escapeCharacter && char == quotation) {
                isInQuotes = !isInQuotes
            } else if (isInQuotes) {
                if (escapeCharacter) {
                    escapeCharacter = false
                } else if( char == ESCAPE) {
                    escapeCharacter = true
                }
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
            if (isInQuotes || char > TAB)
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
                            if (iterateArrayWriteRecursive(iterator, parsedIndex, copiedBytes, notationBalance, searchDepth == 0, data, writeMode, isMultiple)) {
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

                if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    // section responsible for adding attribute at the end of the object if the attribute is not found
                    if ((searchDepth == 0 || notationBalance == advancedOffset) && char == CLOSE_OBJECT && (processedPathIndex + 1) == paths.size && (writeMode == UpdateMode.Upsert || writeMode == UpdateMode.OnlyInsert)) {
                        if (isObjectAttributeFound) {
                            isObjectAttributeFound = false
                        } else {
                            // make sure the the last attribute is an object attribute and not an array index
                            if (arrayIndexes[arrayIndexes.size - 1] == null) {
                                addData(true, data, copiedBytes, paths)
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
                                deleteData(iterator, copiedBytes, notationBalance)
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

                                replaceData(iterator, data, copiedBytes)
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
            val nextChar = iterator.peek() ?: return false
            return nextChar != CLOSE_ARRAY
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

    internal fun getKeys(): Array<String>? {
        if (contentType != "object") {
            errorHandler?.invoke(ErrorInfo(ErrorCode.CannotFindObjectKeys, -1, ""))
            errorHandler = null
            return null
        }

        var isInQuotes = false
        var isEscaped = false
        var grabbedBytes: ByteArray = byteArrayOf()
        var notationBalance = 0
        var keys: Array<String> = arrayOf()

        for (char in jsonData) {
            if (!isEscaped && char == quotation) {
                isInQuotes = !isInQuotes
                if (isInQuotes && notationBalance == 1) {
                    grabbedBytes = byteArrayOf()
                }
            } else if (isInQuotes)  {
                if (isEscaped) {
                    isEscaped = false
                } else if (char == ESCAPE) {
                    isEscaped = true
                }
                if (notationBalance == 1) {
                    grabbedBytes += char
                }
            } else if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                notationBalance += 1
            } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                notationBalance -= 1
            } else if (char == COLON && notationBalance == 1) {
                keys += grabbedBytes.decodeToString()
            }
        }
        return keys
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
                        ValueType(ValueStore(childData =  JSONCollection(getObjectEntries(iterator), false)), "CODE_COLLECTION")
                    } else {
                        ValueType(ValueStore(childData = JSONCollection(getArrayValues(iterator), true)), "CODE_COLLECTION")
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
        return ValueType(ValueStore("no data to retrieve"), "string")
    }

    data class JSONBlockList(@Suppress("ArrayInDataClass") var data: Array<JSONBlock> = arrayOf()) {
        operator fun plusAssign(block: JSONBlock) {
             data = data.plus(block)
        }
    }

    private fun iterateArrayRecursive(iterator: PeekIterator, elementIndex: Int, initialNotationBalance: Int, values: JSONBlockList, shouldRecurse: Boolean, mode: Int, typeConstraint: TypeConstraint): ValueType? {
        var notationBalance = initialNotationBalance
        val stopBalance = initialNotationBalance - 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        var innerItem: ValueType?

        if (elementIndex == 0) {
            val nextChar = iterator.peek() ?: return null
            if (nextChar == CLOSE_ARRAY) {
                return null
            }
            val result = getNextElement(iterator, mode == 1)
            if (mode < 2) {
                if (typeConstraint.isTypeMatch(result.type)) { return result }
                return null
            }
            if (typeConstraint.isTypeMatch(result.type)) {
                values += if (result.value.isBytes) {
                    JSONBlock(result.value.bytes, result.type, this)
                } else {
                    JSONBlock(result.value.string, result.type)
                }
                return null
            }
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
                        innerItem = iterateArrayRecursive(iterator, elementIndex, notationBalance, values, true, mode, typeConstraint)
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
                        if (mode < 2) {
                            if (typeConstraint.isTypeMatch(result.type)) { return result }
                            return null
                        }
                        if (typeConstraint.isTypeMatch(result.type)) {
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
    
    private fun iterateArrayWriteRecursive(iterator: PeekIterator, elementIndex: Int, copyingData: ByteWrapper, initialNotationBalance: Int, shouldRecurse: Boolean, data: ByteArray, updateMode: UpdateMode, isMultiple: Boolean): Boolean {
        var notationBalance = initialNotationBalance
        val stopBalance = initialNotationBalance - 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        var didProcessed = false

        if (elementIndex == 0) {
            val char = iterator.peek() ?: return false
            if (char == CLOSE_ARRAY) {
                copyingData += char
                if (updateMode == UpdateMode.OnlyInsert || updateMode == UpdateMode.Upsert) {
                    addData(false, data, copyingData, mutableListOf())
                    copyingData.dropLast()
                    return true
                }
                copyingData.dropLast()
                return false
            }
            when (updateMode) {
                UpdateMode.Delete -> {
                    deleteData(iterator, copyingData, notationBalance)
                }
                UpdateMode.OnlyInsert -> {
                    addData(false, data, copyingData, mutableListOf(), isIntermediateAdd = true)
                }
                else -> {
                    replaceData(iterator, data, copyingData)
                }
            }
            return true
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
                        didProcessed = iterateArrayWriteRecursive(iterator, elementIndex, copyingData, notationBalance, true, data, updateMode, isMultiple)
                        if (!isMultiple && didProcessed) {
                            return true
                        }
                    }
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (notationBalance == stopBalance) {
                        iterator.moveBack()
                        if (updateMode == UpdateMode.OnlyInsert || updateMode == UpdateMode.Upsert) {
                            addData(false, data, copyingData, mutableListOf())
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
                                deleteData(iterator, copyingData, notationBalance)
                            }
                            UpdateMode.OnlyInsert -> {
                                addData(false, data, copyingData, mutableListOf(), true)
                            }
                            else -> {
                                replaceData(iterator, data, copyingData)
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

    private fun getObjectEntries(iterator: PeekIterator) : List<JSONChild> {
        val values: MutableList<JSONChild> = mutableListOf()
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

    private fun getArrayValues(iterator: PeekIterator) : List<JSONChild> {
        val values: MutableList<JSONChild> = mutableListOf()
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

    private fun replaceData(iterator: PeekIterator, data: ByteArray, copiedBytes: ByteWrapper) {

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
            if (char > TAB)
                copiedBytes += char
        }

        if (type == 1 || type == 2) {
            while (iterator.hasNext()) {
                val char = iterator.nextByte()
                if (isInQuotes) {
                    if (!isEscaping && char == quotation) {
                        if (type == 2) {
                            copiedBytes += data
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
                            copiedBytes += data
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
                    copiedBytes += data
                    iterator.moveBack()
                    return
                }
            }
        }
    }

    private fun isNumber(char: Byte): Boolean {
        return (char in 48..57) || char == DECIMAL || char == MINUS
    }

    private fun deleteData(iterator: PeekIterator, copiedData: ByteWrapper, prevNotationBalance: Int) {
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

}
