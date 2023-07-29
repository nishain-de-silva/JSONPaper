@file:Suppress("unused")
package com.jsonpond
/** JSONPond constants*/
enum class Constants {
    /** JSONPond representation of Null*/
    NULL
}

enum class JSONType (val rawValue: String) {
    STRING("string"), BOOLEAN("boolean"), OBJECT("object"), ARRAY("array"), NUMBER("number"), NULL("null");

    companion object {
        operator fun invoke(rawValue: String) = values().firstOrNull { it.rawValue == rawValue }
    }
}

data class ErrorInfo(val errorCode: ErrorCode, val failedIndex: Int, val path: String) {
    fun explain(): String {
        if (path.isNotEmpty()) {
            return "[$errorCode] occurred on query path ($path)\n\tAt attribute index $failedIndex\n\tReason: ${errorCode.rawValue}"
        }
        return "[$errorCode] occurred on root node itself\n\tReason: ${errorCode.rawValue}"
    }
}

class JSONChild: JSONBlock {
    internal constructor(parent: Base, data: String, type: String): super(data, type, parent)
    internal constructor(parent: Base, data: ByteArray, type: String): super(data, type, parent)

    /**
    Name attribute of this element in the parent object.
     */
    var key = ""

    /**
    Index of this element in the parent array.
     */
    var index = -1
    internal fun setKey(newKey: String): JSONChild {
        key = newKey
        return this
    }

    internal fun setIndex(newIndex: Int) : JSONChild {
        index = newIndex
        return this
    }
}

enum class ErrorCode (val rawValue: String) {
    ObjectKeyNotFound("cannot find object attribute"),
    ArrayIndexNotFound("cannot find given index within array bounds"),
    InvalidArrayIndex("array index is not a integer number"),
    ObjectKeyAlreadyExists("cannot insert because object attribute already exists"),
    NonMatchingDataType("the data type of value of the value does not match with expected data type that is required from query method"),
    NonNestableRootType("root data type is neither array or object and cannot transverse"),
    NonNestedParent("intermediate parent is a leaf node and non-nested. Cannot transverse further"),
    EmptyQueryPath("query path cannot be empty at this query usage"),
    CaptureUnknownElement("the path cannot be end with a intermediate represented token"),
    CannotFindElement("unable to find any element that matches the given path pattern"),
    Other("something went wrong. Target element cannot be found");

    companion object {
        operator fun invoke(rawValue: String) = values().firstOrNull { it.rawValue == rawValue }
    }


    /** Provide string representation of error. */
    fun describe() : String =
        "[${this}] $rawValue"
}

open class JSONBlock {
    private val base: Base = Base()

    companion object {
        private const val INVALID_START_CHARACTER_ERROR = "[JSONPond] the first character of given json content is neither starts with '{' or '['. Make sure the given content is valid JSON"

        /**
            write JSON content from scratch recursively. use mapOf and listOf() to write object and array content respectively.
         */
        fun write(jsonData: Any, prettify: Boolean = true) : JSONBlock {
            val generatedBytes = Base.serializeToBytes(jsonData, 0, if (prettify) 4 else 0, 34)
            if (generatedBytes[0] == 34.toByte()) {
                return JSONBlock(generatedBytes, "string")
            }
            val type = if (jsonData is Map<*, *>) "object" else "array"
            return JSONBlock(generatedBytes, type)
        }
    }

    data class JSONValueTypePair(val value: Any, val type: JSONType)



    /**
        Provide UTF string to read JSON content.
     */
    constructor(jsonString: String) {
        base.identifyStringDelimiter(jsonString)
        base.contentType = when ((jsonString.firstOrNull())) {
            '{' -> "object"
            '[' -> "array"
            else -> {
                println(INVALID_START_CHARACTER_ERROR)
                "string"
            }
        }
        base.jsonData = jsonString.toByteArray()
    }

    /**
        Provide buffer pointer to the JSON content bytes.
     */
    constructor(jsonBufferPointer: ByteArray) {
        base.jsonData = jsonBufferPointer
        base.contentType = when ((base.jsonData.firstOrNull())) {
            123.toByte() -> "object"
            91.toByte() -> "array"
            else -> {
                println(INVALID_START_CHARACTER_ERROR)
                "string"
            }
        }
    }

    // ======= PRIVATE INITIALIZERS =====

    internal constructor(json: String, type: String, parent: Base? = null) {
        if(parent != null && parent.isBubbling) {
            base.isBubbling = parent.errorHandler != null
            base.errorHandler = parent.errorHandler
        }
        base.jsonText = json
        base.contentType = type
        if (base.contentType == "object") {
            base.identifyStringDelimiter(json)
            base.jsonData = json.toByteArray()
        }
    }

    internal constructor(json: ByteArray, type: String, parent: Base? = null) {
        if(parent != null && parent.isBubbling) {
            base.isBubbling = parent.errorHandler != null
            base.errorHandler = parent.errorHandler
        }
        base.jsonText = ""
        base.contentType = type
        base.jsonData = json
    }


    /**
      Set token to represent intermediate paths.
     Intermediate token capture zero or more dynamic intermediate paths. Default token is ???.
    */
    fun setIntermediateGroupToken(representer: String) : JSONBlock {
        if (representer.toIntOrNull() != null) {
            println("[JSONPond] intermediate represent strictly cannot be a number!")
            return this
        }
        base.intermediateSymbol = representer.toByteArray()
        return this
    }

    /**
        Temporary make the next query string to be split by the character given. Useful in case of encountering object attribute containing dot notation in their names.
     */
    fun splitQuery(by: Char) : JSONBlock {
        base.pathSplitter = by
        return this
    }

    /**
        Get string value in the given path.
     */
    fun string(path: String? = null) : String? =
        base.getField(path, "string", { it.string })

    /**
        Get number value in the given path. Note that double instance is given even if
         number is a whole integer type number.
     */
    fun number(path: String? = null, ignoreType: Boolean = false) : Double? =
        base.getField(path, "number", { it.string.toDoubleOrNull() }, ignoreType = ignoreType)

    /**
        Check if the element in the given addressed path represent a null value.
     */
    fun isNull(path: String? = null) : Boolean? {
        val type = if (path == null) base.contentType else base.decodeData(path)?.type ?: return null
        return type == "null"
    }

    /**
        Get JSON object in the given path. Activate ignoreType to parse JSON representable string if possible.
     */
    fun objectEntry(path: String? = null, ignoreType: Boolean = false) : JSONBlock? {
        if (path == null) {
            if(base.contentType == "object")
                return this
            else if(ignoreType && base.contentType == "string") {
                return JSONBlock(base.jsonText, "object", this.base)
            }
            if(base.errorHandler != null) {
                base.errorHandler?.invoke(ErrorInfo(ErrorCode.NonMatchingDataType, -1, ""))
            }
            return null
        }
        val element = base.getField(path, "object", {
            if (ignoreType && it.bytes.isEmpty()) {
                return@getField JSONBlock(it.string, "object", this.base)
            }
            return@getField JSONBlock(it.bytes, "object", this.base)
        }, ignoreType = ignoreType)
        return element
    }

    /**
        Get boolean value in the given path.
     */
    fun bool(path: String? = null, ignoreType: Boolean = false) : Boolean? =
        base.getField(path, "boolean", { it.string == "true" }, ignoreType = ignoreType)

    /**
        Get collection of items either from array or object. Gives array of [JSONChild] which each has property index and key which either has a value based on parent is a object or an array.
     */
    fun collection(path: String? = null, ignoreType: Boolean = false) : Array<JSONChild>? {
        val data = base.decodeData(path ?: "", copyCollectionData = true) ?: return null
        if(ignoreType && data.type == "string") {
            return JSONBlock(data.value.string).collection()
        }
        if(data.type != "CODE_COLLECTION") {
            if(base.errorHandler != null) {
                base.errorHandler?.invoke(
                    ErrorInfo(ErrorCode.NonMatchingDataType,
                        (path?.split(base.pathSplitter)?.size ?: 0) -1,
                        path ?: ""
                    )
                )
            }
            return null
        }
        return data.value.children
    }
    /**
        Check if attribute or element exists in given address path.
     */
    fun isExist(path: String) : Boolean {
        return base.decodeData(path) != null
    }

    /**
        Gives the current instance optionally if the given path exist otherwise return null.
     */
    fun isExistThen(path: String) : JSONBlock? {
        return if(base.decodeData(path) != null) this else null
    }

    /**
        Read JSON element without type constraints.
         Similar to calling string(), array(), object() .etc but without knowing the data type
         of queried value. Returns castable [Any] value along with data type
     */
    fun any(path: String) : JSONValueTypePair? {
        val (value, type) = base.decodeData(path) ?: return null
        if (type == "object") {
            return JSONValueTypePair(JSONBlock(value.bytes, "object"), JSONType("object")!!)
        }
        return JSONValueTypePair(base.resolveValue(value.string, value.bytes, type), JSONType(type)!!)
    }

    /**
        Get collection all values that matches the given path. typeOf parameter to include type constraint else items are not type filtered.
    */
    fun all(path: String, typeOf: JSONType? = null): Array<JSONBlock> {
        return base.decodeData(
            path,
            grabAllPaths =  true,
            multiCollectionTypeConstraint = typeOf
        )?.value?.array ?: arrayOf()
    }

    /** Get the data type of the value held by the content of this node. */
    fun type() : JSONType =
        JSONType(base.contentType)!!

    /** Attach a query fail listener to the next read or write query. Listener will be removed after single use.
     *Bubbling enable inline generated instances to inherit this error handler.
     */
    fun onQueryFail(handler: (ErrorInfo) -> Unit, bubbling: Boolean = false) : JSONBlock {
        base.errorHandler = handler
        base.isBubbling = bubbling
        return this
    }

    /** Update the given given query path.*/
        fun replace(path: String, data: Any, multiple: Boolean = false) : JSONBlock {
        base.write(path, data, UpdateMode.OnlyUpdate, multiple)
        base.errorInfo?.apply {
            base.errorHandler?.invoke(ErrorInfo(this.first, this.second, path))
            base.errorHandler = null
        }
        return this
    }

    /** Insert an element to the given query path. Last segment of the path should address to attribute name / array index to insert on objects / arrays.
     */
    fun insert(path: String, data: Any, multiple: Boolean = false) : JSONBlock {
        base.write(path, data, UpdateMode.OnlyInsert, multiple)
        base.errorInfo?.apply {
            base.errorHandler?.invoke(ErrorInfo(this.first, this.second, path))
            base.errorHandler = null
        }
        return this
    }

    /** Update or insert data to node of the given query path.*/
    fun upsert(path: String, data: Any, multiple: Boolean = false) : JSONBlock {
        base.write(path, data, UpdateMode.Upsert, multiple)
        base.errorInfo?.apply {
            base.errorHandler?.invoke(ErrorInfo(this.first, this.second, path))
            base.errorHandler = null
        }
        return this
    }

    /** delete path if exists. Return if delete successfully or not.*/
    fun delete(path: String, multiple: Boolean = false) : JSONBlock {
        base.write(path, 0, UpdateMode.Delete, multiple)
        base.errorInfo?.apply {
            base.errorHandler?.invoke(ErrorInfo(this.first, this.second, path))
            base.errorHandler = null
        }
        return this
    }

    /** Returns the content data as [ByteArray], map function parameter function optionally use to map the result with generic type.*/
    fun <R> bytes(mapFunction: ((ByteArray) -> R)) : R {
        return mapFunction(base.jsonData)
    }

    /** Returns the content data as [ByteArray], map function parameter function optionally use to map the result with generic type.*/
    fun bytes() : ByteArray {
        return base.jsonData
    }



    /** Convert the selected element content to representable [String].*/
    fun stringify(path: String, tabSize: Int = 3) : String? {
        val result = base.decodeData(path)
        if (result != null) {
            return if (result.type == "object" || result.type == "array") base.prettifyContent(result.value.bytes, tabSize) else result.value.string
        }
        return null
    }

    /** Convert the selected element content to representable [String]. */
    fun stringify(tabSize: Int = 3) : String =
        if (base.contentType == "object" || base.contentType == "array") base.prettifyContent(base.jsonData, tabSize) else base.jsonText

    /**
     Get the natural value of JSON node. Elements expressed in associated Kotlin type except
     for null represented in [Constants.NULL] based on their data type. Both array and
     object are represented by [List] and [Map] respectively and their subElements are
     parsed recursively until to singular values.
     */
    fun parse() : Any {
        if (base.contentType == "object" || base.contentType == "array") {
            val iterator = PeekIterator(base.jsonData)
            return base.getStructuredData(iterator, firstCharacter = iterator.nextByte()).value.tree
        }
        return base.resolveValue(base.jsonText, base.jsonData, base.contentType)
    }

    /** Get natural value of an element for given path with data type. Similar to [parse]. */
    fun parseWithType(path: String) : JSONValueTypePair? {
        base.extractInnerContent = true
        val (value, type) = base.decodeData(path) ?: return null
        base.extractInnerContent = false
        if ((type == "object" || type == "array")) {
            return JSONValueTypePair(value.tree, JSONType(type)!!)
        }
        return JSONValueTypePair(base.resolveValue(value.string, value.bytes, type), JSONType(type)!!)
    }
    /**
     Get the natural value of JSON node. Elements expressed in associated Kotlin type except
     for null represented in [Constants.NULL] based on their data type. Both array and
     object are represented by [Array] and [Map] respectively and their subElements are
     parsed recursively until to singular values.
     */
    fun parse(path: String) : Any? {
        base.extractInnerContent = true
        val (value, type) = base.decodeData(path) ?: return null
        base.extractInnerContent = false
        if (type == "object" || type == "array") {
            return value.tree
        }
        return base.resolveValue(value.string, value.bytes, type)
    }

    /** Capture the node addressed by the given path. */
    fun capture(path: String) : JSONBlock? {
        val result = base.decodeData(path) ?: return null
        return if (result.value.bytes.isEmpty())
                JSONBlock(result.value.string, result.type, this.base)
        else JSONBlock(result.value.bytes, result.type, this.base)
    }
}
