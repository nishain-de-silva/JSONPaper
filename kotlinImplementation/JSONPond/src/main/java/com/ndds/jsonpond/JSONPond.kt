package com.ndds.JSONPond

/// JSONPond representation of Null
enum class Constants {
    NULL
}

/// JSONPond representation of Null
val Null = Constants.NULL
enum class JSONType (val rawValue: String) {
    STRING("string"), BOOLEAN("boolean"), OBJECT("object"), ARRAY("array"), NUMBER("number"), NULL("null");

    companion object {
        operator fun invoke(rawValue: String) = values().firstOrNull { it.rawValue == rawValue }
    }
}

class JSONPond {
    companion object {
        private const val INVALID_START_CHARACTER_ERROR = "[JSONPond] the first character of given json content is neither starts with '{' or '['. Make sure the given content is valid JSON"

        private const val COMMA: Byte = 44
        private const val TAB: Byte = 32
        private const val NEW_LINE: Byte = 10
        private const val OPEN_OBJECT: Byte = 123
        private const val OPEN_ARRAY: Byte = 91
        private const val CLOSE_OBJECT: Byte = 125
        private const val CLOSE_ARRAY: Byte = 93
        private const val LETTER_N: Byte = 110
        private const val LETTER_T: Byte = 116
        private const val LETTER_F: Byte = 102
        private const val QUOTATION: Byte = 34
        private const val COLON: Byte = 58
        private const val DECIMAL: Byte = 46
        private const val MINUS: Byte = 45
        private const val ESCAPE: Byte = 92

        fun List<ByteArray>.joined(seperator: ByteArray): ByteArray {
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

        private fun _serializeToBytes(node: Any?, index: Int, tabCount: Int) : ByteArray {
            when (node) {
                is Map<*, *> -> {
                    val innerContent: List<ByteArray> = node.map {
                        byteArrayOf(QUOTATION) +
                                it.key.toString().toByteArray() +
                                (if (tabCount != 0) byteArrayOf(QUOTATION, COLON, TAB) else byteArrayOf(QUOTATION, COLON)) +
                                _serializeToBytes(it.value!!, index + 1, tabCount)
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
                    return (byteArrayOf(OPEN_OBJECT) + (innerContent.joined(byteArrayOf(COMMA)))) + byteArrayOf(CLOSE_OBJECT)
                }
                is List<*> -> {
                    val innerContent = node.map { _serializeToBytes(it!!, index + 1, tabCount) }
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
                    return (byteArrayOf(OPEN_ARRAY) + innerContent.joined(byteArrayOf(COMMA))) + byteArrayOf(CLOSE_ARRAY)
                }
                is String -> {
                    return byteArrayOf(QUOTATION) + node.toByteArray() + QUOTATION
                }
                is Boolean -> {
                    return if (node) byteArrayOf(LETTER_T, 114, 117, 101) else byteArrayOf(LETTER_F, 97, 108, 115, 101)
                }
                is Number -> {
                    return node.toString().toByteArray()
                }
                Constants.NULL -> {
                    return byteArrayOf(LETTER_N, 117, 108, 108)
                }
                else -> {
                    return byteArrayOf(QUOTATION, 35, 73, 78, 86, 65, 76, 73, 68, 95, 84, 89, 80, 69, QUOTATION)
                }
            }
        }

        fun write(jsonData: Any, prettify: Boolean = true) : JSONPond {
            val type = if (jsonData is Map<*, *>) "object" else "array"
            return JSONPond(_serializeToBytes(jsonData, 0, if (prettify) 4 else 0), type)
        }

        private  fun fillTab(repeatCount: Int) : ByteArray {
            val array = ByteArray(repeatCount)
            array.fill(TAB)
            return  array
        }
    }

    private var jsonText: String = ""
    private var jsonData: ByteArray = byteArrayOf()
    private var contentType: String
    private var extractInnerContent = false
    private var intermediateSymbol: ByteArray = byteArrayOf(63, 63, 63)
    private var errorHandler: ((error: ErrorCode, occurredIndex: Int) -> Unit)? = null
    private var errorInfo:  Pair<ErrorCode, Int>? = null
    private var pathSplitter: Char = '.'
    private var typeMismatchWarningCount = 0
    private var stringQuotationDelimter: QuotationDelimiter = QuotationDelimiter.singleQuotation


    /*
        Name attribute of this element in the parent object.
     */
    var key = ""

    /*
        Index of this element in the parent array.
     */
    var index = -1
    private fun setKey(newKey: String) : JSONPond {
        key = newKey
        return this
    }

    private fun setIndex(newIndex: Int) : JSONPond {
        index = newIndex
        return this
    }

    private data class ValueType(val value: ValueStore, val type: String)

    private class ValueStore {
        var string: String = ""
        var bytes: ByteArray = byteArrayOf()
        var array: Array<JSONPond> = arrayOf()
        var tree: Any = listOf(0)

        constructor(input: String) {
            string = input
        }

        constructor(text: String, data: ByteArray) {
            string = text
            bytes = data
        }

        constructor(arrayData: Array<JSONPond>) {
            array = arrayData
        }

        constructor(data: ByteWrapper) {
            bytes = data.bytes
        }

        constructor(parsedData: Any) {
            tree = parsedData
        }
    }

    /*
        Provide UTF string to read JSON content.
     */
    constructor(jsonString: String) {
        jsonText = jsonString
        contentType = when ((jsonText.first())) {
            '{' -> "object"
            '[' -> "array"
            else -> {
                print(INVALID_START_CHARACTER_ERROR)
                "string"
            }
        }
        jsonData = jsonString.toByteArray()
    }

    /*
        Provide buffer pointer to the JSON content bytes.
     */
    constructor(jsonBufferPointer: ByteArray) {
        jsonData = jsonBufferPointer
        contentType = when ((jsonData.firstOrNull())) {
            OPEN_OBJECT -> "object"
            OPEN_ARRAY -> "array"
            else -> {
                print(INVALID_START_CHARACTER_ERROR)
                "string"
            }
        }
    }

    // ======= PRIVATE INITIALIZERS =====

    private constructor(json: String, type: String) {
        jsonText = json
        contentType = type
        if (contentType == "object") {
            jsonData = json.toByteArray()
        }
    }

    private constructor(json: ByteArray, type: String) {
        jsonText = ""
        contentType = type
        jsonData = json
    }

    /*
      Set token to represent intermediate paths.
     Intermediate token capture zero or more dynamic intermediate paths. Default token is ???.
    */
    fun setIntermediateRepresent(representer: String) : JSONPond {
        if (representer.toIntOrNull() != null) {
            print("[JSONPond] intermediate represent strictly cannot be a number!")
            return this
        }
        intermediateSymbol = representer.toByteArray()
        return this
    }

    /*
        Temporary make the next query string to be split by the character given. Useful in case of encountering object attribute containing dot notation in their names.
     */
    fun splitQuery(by: Char) : JSONPond {
        pathSplitter = by
        return this
    }

    public fun terminateNestedString(by: QuotationDelimiter) : JSONPond {
        stringQuotationDelimter = by
        return this
    }
    
    private fun <T> getField(path: String?, fieldName: String, mapper: (ValueStore) -> T?, ignoreType: Boolean = false) : T? {
        val (data, type) = if (path == null) ValueType(ValueStore(jsonText, jsonData), contentType) else decodeData(
            path
        ) ?: return null
        if (!ignoreType && type != fieldName) {
            if (typeMismatchWarningCount != 3) {
                print("[JSONPond] type constrained query expected $fieldName but $type type value was read instead therefore returned nil. This warning will not be shown after 3 times per instance")
                typeMismatchWarningCount += 1
            }
            return null
        }
        return mapper(data)
    }

    /*
        Get string value in the given path.
     */
    fun string(path: String? = null) : String? =
        getField(path, "string", { it.string })

    /*
        Get number value in the given path. Note that double instance is given even if
         number is a whole integer type number.
     */
    fun number(path: String? = null, ignoreType: Boolean = false) : Double? =
        getField(path, "number", { it.string.toDoubleOrNull() }, ignoreType = ignoreType)

    /*
        Check if the element in the given addressed path represent a null value.
     */
    fun isNull(path: String? = null) : Boolean? {
        val type = if (path == null) contentType else decodeData(path)?.type ?: return null
        return type == "null"
    }

    /*
        Get object in the given path. Activate ignoreType to parse string as json object.
     */
    fun Object(path: String? = null, ignoreType: Boolean = false) : JSONPond? {
        if (path == null) {
            return this
        }
        return getField(path, "object", { if (ignoreType) JSONPond(replaceEscapedQuotations(it.string), "object") else JSONPond(it.bytes, "object") }, ignoreType = ignoreType)
    }

    /*
        Get boolean value in the given path.
     */
    fun bool(path: String? = null, ignoreType: Boolean = false) : Boolean? =
        getField(path, "boolean", { it.string == "true" }, ignoreType = ignoreType)

    /*
        Get collection of items either from array or object
     */
        fun collection(path: String? = null, ignoreType: Boolean = false) : Array<JSONPond>? {
            if (ignoreType) {
                val content = getField(path, "string", {replaceEscapedQuotations(it.string)})
                    ?: return null
                return JSONPond(content).collection()
            }
            val data = decodeData(path ?: "", copyCollectionData = true)
            if(data?.type != "CODE_COLLECTION") {
                return null
            }
            return data.value.array
        }
    /*
        Check if attribute or element exists in given address path.
     */
    fun isExist(path: String) : Boolean {
        return decodeData(path) != null
    }

    private fun resolveValue(stringData: String, byteData: ByteArray, type: String, serialize: Boolean = false) : Any {
        return when ((type)) {
            "number" -> stringData.toDouble()
            "array" -> JSONPond(byteData, "array").collection()!!
            "boolean" -> stringData == "true"
            "null" -> Constants.NULL
            else -> stringData
        }
    }

    /*
        Read JSON element without type constraints.
         Similar to calling string(), array(), object() .etc but without knowing the data type
         of queried value. Returns castable any value along with data type
     */
    fun any(path: String) : Pair<Any, JSONType>? {
        val (value, type) = decodeData(path) ?: return null
        if (type == "object") {
            return Pair(JSONPond(value.bytes, "object"), JSONType("object")!!)
        }
        return Pair(resolveValue(value.string, value.bytes, type), JSONType(type)!!)
    }

    fun type() : JSONType =
        JSONType(contentType)!!

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

    private enum class UpdateMode {
        upsert,
        onlyUpdate,
        onlyInsert,
        delete
    }
    enum class ErrorCode (val rawValue: String) {
        objectKeyNotFound("cannot find object attribute"),
        arrayIndexNotFound("cannot find given index within array bounds"),
        invalidArrayIndex("array index is not a integer number"),
        objectKeyAlreadyExists("cannot insert because object attribute already exists"),
        nonNestableRootType("root data type is neither array or object and cannot transverse"),
        nonNestedParent("intermediate parent is a leaf node and non-nested. Cannot transverse further"),
        emptyQueryPath("query path cannot be empty at this query usage"),
        captureUnknownElement("the path cannot be end with a intermediate representer"),
        other("something went wrong. Target element cannot be found");

        companion object {
            operator fun invoke(rawValue: String) = values().firstOrNull { it.rawValue == rawValue }
        }


        /// Provide string representation of error.
        fun describe() : String =
            "[${this}] ${rawValue}"
    }

    enum class QuotationDelimiter {
        singleQuotation,
        escapedDoubleQuotation
    }

    private fun _deleteData(iterator: ByteIterator, copiedData: ByteWrapper, tabUnitCount: Int, prevNotationBalnce: Int, pathCount: Int) {
        var didRemovedFirstComma = false
        var isInQuotes = false
        var notationBalance = prevNotationBalnce
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

    private fun _splitPath(path: String) : MutableList<ByteArray> {
        val paths: MutableList<ByteArray> = path.split(pathSplitter).map { it.toByteArray() }.toMutableList()
        if (pathSplitter != '.') {
            pathSplitter = '.'
        }
        return paths
    }

    /// Attach a query fail listener to the next read or write query. Listener will be removed after single use.
    fun onQueryFail(handler: (error: ErrorCode, querySegmentIndex: Int) -> Unit) : JSONPond {
        errorHandler = handler
        return this
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
            val endKeyPhrase: ByteArray = if (tabUnitCount == 0) byteArrayOf(QUOTATION, COLON) else byteArrayOf(QUOTATION, COLON, TAB)
            copiedBytes += endKeyPhrase
        }
        var bytesToAdd = _serializeToBytes(dataToAdd, paths.size, tabUnitCount)
        if (!isIntermediateAdd) {
            if (tabUnitCount != 0) {
                bytesToAdd += NEW_LINE
                bytesToAdd += fillTab((paths.size - 1) * tabUnitCount)
            }
            bytesToAdd += if (isInObject) CLOSE_OBJECT else CLOSE_ARRAY
        } else {
            bytesToAdd += COMMA
        }
        _continueCopyData(iterator, copiedBytes, bytesToAdd, dataType = 4)
        return null
    }

    /// Update the given given query path.
    fun update(path: String, data: Any) : JSONPond {
        errorInfo = _write(path, data, writeMode = UpdateMode.onlyUpdate)
        errorInfo?.apply {
            errorHandler?.invoke(this.first, this.second)
            errorHandler = null
        }
        return this
    }

    /// Insert an element to the given query path. If the last segment of the path is an array then the element will be added to the array else if it's a nonexistent key then the key attribute will be added to the object.
    fun insert(path: String, data: Any) : JSONPond {
        errorInfo = _write(path, data, writeMode = UpdateMode.onlyInsert)
        errorInfo?.apply {
            errorHandler?.invoke(this.first, this.second)
            errorHandler = null
        }
        return this
    }

    /// Update or insert data to node of the given query path.
    fun upsert(path: String, data: Any) : JSONPond {
        errorInfo = _write(path, data, writeMode = UpdateMode.upsert)
        errorInfo?.apply {
            errorHandler?.invoke(this.first, this.second)
            errorHandler = null
        }
        return this
    }

    /// delete path if exists. Return if delete successfull or not.
    fun delete(path: String) : JSONPond {
        errorInfo = _write(path, 0, writeMode = UpdateMode.delete)
        errorInfo?.apply {
            errorHandler?.invoke(this.first, this.second)
            errorHandler = null
        }
        return this
    }

    /// Returns the content data as [Byte], map function parameter function optionally use to map the result with generic type.
    fun <R> bytes(mapFunction: ((ByteArray) -> R)) : R {
        return mapFunction(jsonData)
    }

    /// Returns the content data as [Byte], map function parameter function optionally use to map the result with generic type.
    fun bytes() : ByteArray {
        return jsonData
    }


    private fun _write(path: String, data: Any, writeMode: UpdateMode) : Pair<ErrorCode, Int>? {
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
        val paths: List<ByteArray> = _splitPath(path)
        var copiedBytes = ByteWrapper(byteArrayOf())
        var searchValue = 0
        var iterator = jsonData.iterator()
        if (paths.size == 0) {
            return Pair(ErrorCode.emptyQueryPath, -1)
        }
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
           
            if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    notationBalance += 1
                    if (searchValue == 1) {
                        val bytesToAdd = _serializeToBytes(data, paths.size, tabUnitCount)
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
                        } else if (processedindex == (paths.size - 1) && (writeMode == UpdateMode.upsert || writeMode == UpdateMode.onlyInsert)) {
                            return _addData(false, data, iterator, copiedBytes, tabUnitCount, paths)
                        }
                        continue
                    } else if (searchValue != 0) {
                        searchValue = 0
                    }
                } else if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    if (processedindex == notationBalance) {
                        if (processedindex + 1 == paths.size && (writeMode == UpdateMode.upsert || writeMode == UpdateMode.onlyInsert)) {
                            return _addData(char == CLOSE_OBJECT, data, iterator, copiedBytes, tabUnitCount, paths)
                        }
                        return Pair(if (char == CLOSE_OBJECT) ErrorCode.objectKeyNotFound else ErrorCode.arrayIndexNotFound, processedindex)
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
                    val bytesToAdd = _serializeToBytes(data, paths.size, tabUnitCount)
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
                        return Pair(ErrorCode.objectKeyAlreadyExists, paths.size - 2)
                    }
                    val bytesToAdd = _serializeToBytes(data, paths.size, tabUnitCount)
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


    /// Convert the selected element content to representable string.
    fun stringify(path: String) : String? {
        val result = decodeData(path)
        if (result != null) {
            return if (result.value.bytes.isEmpty()) result.value.string else result.value.bytes.decodeToString()
        }
        return null
    }

    /// Convert the selected element content to representable string.
    fun stringify() : String =
        if (jsonData.isEmpty()) jsonText else jsonData.decodeToString()

    /// Get the natural value of JSON node. Elements expressed in associated swift type except
    /// for null represented in `.Constants.NULL` based on their data type. Both array and
    /// object are represented by dictionary and array respectively and their subelements are
    /// parsed recursively until to singular values.
    fun parse() : Any {
        if (contentType == "object" || contentType == "array") {
            val iterator = jsonData.iterator()
            return _getStructuredData(iterator, firstCharacter = iterator.nextByte()).value.tree
        }
        return resolveValue(jsonText, jsonData, contentType)
    }

    /// Get natural value of an element for given path with data type. Similar to parse(path:).
    fun parseWithType(path: String) : Pair<Any, JSONType>? {
        extractInnerContent = true
        val (value, type) = decodeData(path) ?: return null
        extractInnerContent = false
        if ((type == "object" || type == "array")) {
            return Pair(value.tree, JSONType(type)!!)
        }
        return Pair(resolveValue(value.string, value.bytes, type), JSONType(type)!!)
    }

    /// Get the natural value of JSON node. Elements expressed in associated swift type except
    /// for null represented in `.Constants.NULL` based on their data type. Both array and
    /// object are represented by dictionary and array respectively and their subelements are
    /// parsed recursively until to singular values.
    fun parse(path: String) : Any? {
        extractInnerContent = true
        val (value, type) = decodeData(path) ?: return null
        extractInnerContent = false
        if (type == "object" || type == "array") {
            return value.tree
        }
        return resolveValue(value.string, value.bytes, type)
    }

    /// Capture the node addressed by the given path.
    fun capture(path: String) : JSONPond? {
        val result = decodeData(path) ?: return null
        return if (result.value.bytes.isEmpty()) JSONPond(result.value.string, result.type) else JSONPond(result.value.bytes, result.type)
    }

    private fun decodeData(inputPath: String, copyCollectionData: Boolean = false) : ValueType? {
        val results = exploreData(inputPath, copyCollectionData)
        errorInfo?.apply {
            errorHandler?.invoke(this.first, this.second)
            errorHandler = null
        }
        return results
    }

    private fun _asString(bytes: ByteArray) : String =
        bytes.decodeToString()

    private fun _trimSpace(input: String) : String {
        var newString = input
        while ((newString.last().isWhitespace())) {
            newString = newString.dropLast(1)
        }
        return newString
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

    class CollectionHolder(isObject: Boolean) {
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


    private fun _getStructuredData(iterator: ByteIterator, firstCharacter: Byte) : ValueType {
        var stack: MutableList<CollectionHolder> = mutableListOf()
        var isInQuotes = false
        var grabbedKey = ""
        var isGrabbingText = false
        var grabbedText = ""
        var notationBalance = 1
        var shouldProccessObjectValue = false
        var escapeCharacter = false
        if (firstCharacter == OPEN_OBJECT) {
            stack += CollectionHolder(isObject = true)
        } else {
            stack += CollectionHolder(isObject = false)
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
                    shouldProccessObjectValue = false
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
                        return if (stack.first().type == "object") ValueType(ValueStore(parsedData = stack.last().objectCollection), "object") else ValueType(ValueStore(parsedData = stack.last().arrayCollection), "array")
                    }
                    shouldProccessObjectValue = false
                    val child = stack.removeLast()
                    if (stack.last().type == "object") {
                        stack.last().assignChildToObject(child)
                    } else {
                        stack.last().appendChildToArray(child)
                    }
                } else if (char == COLON) {
                    shouldProccessObjectValue = true
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
                    shouldProccessObjectValue = false
                }
            }
            if (!escapeCharacter && char == QUOTATION) {
                isInQuotes = !isInQuotes
                isGrabbingText = isInQuotes
                if (isGrabbingText) {
                    grabbedText = ""
                } else {
                    if (stack.last().type == "object") {
                        if (shouldProccessObjectValue) {
                            stack.last().objectCollection["fsdff"] = QUOTATION
                            stack.last().objectCollection[grabbedKey] = grabbedText
                        }
                    } else {
                        stack.last().arrayCollection += grabbedText
                    }
                    shouldProccessObjectValue = false
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
        return ValueType(ValueStore(parsedData = byteArrayOf()), if (firstCharacter == OPEN_OBJECT) "object" else "array")
    }

    private fun _iterateArray(iterator: ByteIterator, elementIndex: Int) : Boolean {
        var notationBalance = 1
        var escapeChracter = false
        var isQuotes = false
        var cursorIndex = 0
        if (elementIndex == 0) {
            return true
        }
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!escapeChracter && char == QUOTATION) {
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
            if (escapeChracter) {
                escapeChracter = false
            } else if (char == ESCAPE) {
                escapeChracter = true
            }
        }
        return false
    }

    private fun _iterateArrayWrite(iterator: ByteIterator, elementIndex: Int, copyingData: ByteWrapper) : Boolean {
        var notationBalance = 1
        var escapeChracter = false
        var isQuotes = false
        var cursorIndex = 0
        copyingData += OPEN_ARRAY
        if (elementIndex == 0) {
            return true
        }

        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!escapeChracter && char == QUOTATION) {
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
            if (escapeChracter) {
                escapeChracter = false
            } else if (char == ESCAPE) {
                escapeChracter = true
            }
            copyingData += char
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
            }
            if(isEscape) {
                isEscape = false
            } else if (char == ESCAPE) {
                isEscape = true
            }
            copiedData += char
        }
    }

    private fun _getObjectEntries(iterator: ByteIterator) : Array<JSONPond> {
        var values: Array<JSONPond> = arrayOf()
        var bytes: ByteWrapper
        var text = ""
        var isGrabbing = false
        var dataType = ""
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
                    isGrabbing = true
                    continue
                } else {
                    if (shouldGrabItem) {
                        shouldGrabItem = false
                        values += JSONPond(text, "string").setKey(grabbedKey)
                    }
                    isGrabbing = false
                }
            } else if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    bytes = ByteWrapper(byteArrayOf(char))
                    dataType = if (char == OPEN_OBJECT) "object" else "array"
                    _grabData(bytes, iterator)
                    values += JSONPond(bytes.bytes, dataType).setKey(grabbedKey)
                    shouldGrabItem = false
                    continue
                }
                if (shouldGrabItem) {
                    val result =  _getPrimitive(iterator, char)
                    if(result != null) {
                        values += JSONPond(result.second,result.first).setKey(grabbedKey)
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
            } else if (isGrabbing) {
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

    private fun _getArrayValues(iterator: ByteIterator) : Array<JSONPond> {
        var values: Array<JSONPond> = arrayOf()
        var bytes: ByteWrapper = ByteWrapper(byteArrayOf())
        var text: String = ""
        var isGrabbing = false
        var dataType = ""
        var isQuotes = false
        var isEscaping = false
        var index = 0
        while (iterator.hasNext()) {
            val char = iterator.nextByte()
            if (!isEscaping && char == QUOTATION) {
                isQuotes = !isQuotes
                if (isQuotes) {
                    text = ""
                    isGrabbing = true
                    continue
                } else {
                    values += JSONPond(text, "string").setIndex(index)
                    index += 1
                    isGrabbing = false
                }
            } else if (!isQuotes) {
                if (char == OPEN_OBJECT || char == OPEN_ARRAY) {
                    bytes = ByteWrapper(byteArrayOf(char))
                    dataType = if (char == OPEN_OBJECT) "object" else "array"
                    _grabData(bytes, iterator)
                    values += JSONPond(bytes.bytes, dataType).setIndex(index)
                    index += 1
                    continue
                }
                val result = _getPrimitive(iterator, char)
                if(result != null) {
                    values += JSONPond(result.second, result.first).setIndex(index)
                    index += 1
                    if(result.third) {
                        return values
                    }
                } else if (char == CLOSE_ARRAY) {
                    return values
                }
            } else if (isGrabbing) {
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

    private fun _getPrimitive(iterator: ByteIterator, firstCharacter: Byte) : Triple<String, String, Boolean>? {
        if (firstCharacter == LETTER_T) {
            return Triple("boolean", "true", false)
        } else if (firstCharacter == LETTER_F) {
            return Triple("boolean", "false", false)
        } else if (firstCharacter == LETTER_N) {
            return Triple("null", "null", false)
        } else if ((firstCharacter > 47 && firstCharacter < COLON) || firstCharacter == MINUS) {
            var didContainerClosed = false
            var copiedNumber = "${firstCharacter.toInt().toChar()}"
            while (iterator.hasNext()) {
                val num = iterator.nextByte()
                if ((num > 47 && num < COLON) || num == DECIMAL) {
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

    class ByteWrapper(var bytes: ByteArray) {
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

    private fun exploreData(inputPath: String, copyCollectionData: Boolean) : ValueType? {
        errorInfo = null
        if (!(contentType == "object" || contentType == "array")) {
            errorInfo = Pair(ErrorCode.nonNestableRootType, 0)
            return null
        }

        fun <T> Array<T>.dropLast() : Array<T> {
            return this.copyOfRange(0, lastIndex)
        }

        val paths: MutableList<ByteArray> = _splitPath(inputPath)
        var processedPathIndex = 0
        var isNavigatingUnknownPath = false
        var advancedOffset = 0
        var tranversalHistory: Array<Pair<Int, Int>> = arrayOf()
        var isInQuotes = false
        var startSearchValue = false
        var isGrabbingText = false
        var grabbedText = ""
        var grabbedBytes: ByteWrapper
        var grabbingKey: ByteArray = byteArrayOf()
        var needProccessKey = false
        var isGrabbingKey = false
        var notationBalance = 0
        var grabbingDataType: String = "string"
        var escapeCharacter: Boolean = false

        if (paths.size == 0 && !copyCollectionData) {
            errorInfo = Pair(ErrorCode.emptyQueryPath, -1)
            return null
        }
        if (paths.last().contentEquals(intermediateSymbol)) {
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
                                return ValueType(ValueStore(arrayData = _getObjectEntries(iterator)), "CODE_COLLECTION")
                            }
                            return ValueType(ValueStore(arrayData = _getArrayValues(iterator)), "CODE_COLLECTION")
                        }
                        grabbedBytes = ByteWrapper(byteArrayOf(char))
                        grabbingDataType = if (char == OPEN_OBJECT) "object" else "array"
                        _grabData(grabbedBytes, iterator)
                        return ValueType(ValueStore(grabbedBytes), grabbingDataType)
                    }
                    // intiate elements counting inside array on reaching open bracket...
                    if (char == OPEN_ARRAY && ((advancedOffset + 1) == notationBalance || isNavigatingUnknownPath)) {
                        val parsedIndex = _toNumber(paths[processedPathIndex])
                        // occur when trying to access element of array with non-number index
                        if (parsedIndex == null) {
                            if (paths[processedPathIndex].contentEquals(intermediateSymbol)) {
                                paths.removeAt(processedPathIndex)
                                isNavigatingUnknownPath = true
                                tranversalHistory += Pair(processedPathIndex, advancedOffset)
                                continue
                            } else if (isNavigatingUnknownPath) {
                                continue
                            }
                            errorInfo = Pair(ErrorCode.invalidArrayIndex, processedPathIndex)
                            return null
                        }
                        if (isNavigatingUnknownPath) {
                            isNavigatingUnknownPath = false
                            advancedOffset = notationBalance - 1
                        }
                        if (!_iterateArray(iterator, elementIndex = parsedIndex)) {
                            if (tranversalHistory.isNotEmpty()) {
                                if (tranversalHistory.size != 1) {
                                    tranversalHistory = tranversalHistory.dropLast()
                                    paths.add(processedPathIndex, intermediateSymbol)
                                }
                                tranversalHistory[tranversalHistory.size - 1].apply {
                                    processedPathIndex = this.first
                                    advancedOffset = this.second
                                }
                                isNavigatingUnknownPath = true
                                continue
                            }
                            errorInfo = Pair(ErrorCode.arrayIndexNotFound, paths.size - 1)
                            return null
                        }
                        processedPathIndex += 1
                        advancedOffset += 1
                        startSearchValue = true
                    } else {
                        // move to next nest object and start looking attribute key on next nested object...
                        startSearchValue = false
                        if (paths[processedPathIndex].contentEquals(intermediateSymbol)) {
                            isNavigatingUnknownPath = true
                            tranversalHistory += Pair(processedPathIndex, advancedOffset)
                            paths.removeAt(processedPathIndex)
                        }
                    }
                    continue
                }
                if (char == CLOSE_OBJECT || char == CLOSE_ARRAY) {
                    notationBalance -= 1
                    // occur after all element in focused array or object is finished searching...
                    if (notationBalance == advancedOffset) {
                        // exit occur after no matching key is found in object
                        if (char == CLOSE_OBJECT) {
                            if (tranversalHistory.isNotEmpty()) {
                                if (tranversalHistory.size != 1) {
                                    tranversalHistory = tranversalHistory.dropLast()
                                    paths.add(processedPathIndex, intermediateSymbol)
                                }
                                tranversalHistory[tranversalHistory.size - 1].apply {
                                    processedPathIndex = this.first
                                    advancedOffset = this.second
                                }
                                isNavigatingUnknownPath = true
                                continue
                            }
                            errorInfo = Pair(ErrorCode.objectKeyNotFound, paths.size - 1)
                            return null
                        }
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
                        // if not the last proccesed value skip caturing value
                        if (processedPathIndex != paths.size) {
                            errorInfo = Pair(ErrorCode.nonNestedParent, processedPathIndex - 1)
                            return null
                        }
                        isGrabbingText = !isGrabbingText
                        if (!isGrabbingText) {
                            return ValueType(ValueStore(grabbedText), "string")
                        } else {
                            grabbingDataType = "string"
                            grabbedText = ""
                        }
                    } else // used to copy values true, false, null and number
                    {
                        // ========== HANDLING GRABBING NUMBERS, BOOLEANS AND NULL
                        if (!isInQuotes && !isGrabbingText) {
                            val result = _getPrimitive(iterator, char)
                            if (result != null) {
                                if (processedPathIndex != paths.size) {
                                    errorInfo = Pair(ErrorCode.nonNestedParent, processedPathIndex - 1)
                                    return null
                                }
                                return ValueType(ValueStore(result.second), result.first)
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
                        isGrabbingKey = !isGrabbingKey
                        if (isGrabbingKey) {
                            grabbingKey = byteArrayOf()
                        } else {
                            needProccessKey = true
                        }
                    }
                } else if (isGrabbingKey) {
                    grabbingKey += char
                } else if (needProccessKey && char == COLON) {
                    needProccessKey = false
                    // if found start searching for object value for object key
                    if (grabbingKey.contentEquals(paths[processedPathIndex])) {
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

    private fun replaceEscapedQuotations(text: String) : String {
        var replaced = ""
        var escaped = false

        if (stringQuotationDelimter == QuotationDelimiter.escapedDoubleQuotation) {
            for (char in text) {
                if (char == '\\') {
                    escaped = true
                } else if (escaped) {
                    if (char == '\"') {
                        replaced += "\""
                    } else {
                        replaced += "\\"
                        replaced += char
                    }
                    escaped = false
                } else {
                    replaced += char
                }
            }
        } else {
            for (char in text) {
                if (char == '\'') {
                    replaced += "\""
                } else {
                    replaced += char
                }
            }
        }
        return replaced
    }
}