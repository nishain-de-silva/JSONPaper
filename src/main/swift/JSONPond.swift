import Foundation
/// JSONBlock representation of Null
public enum Constants {
    case NULL
}

public enum JSONType: String {
    case string = "string"
    case boolean = "boolean"
    case object = "object"
    case array = "array"
    case number = "number"
    case null = "null"
    
    init(_ v: String) {
        self = .init(rawValue: v)!
    }
}

public enum ErrorCode: String {
    case objectKeyNotFound = "cannot find object attribute"
    case arrayIndexNotFound = "cannot find given index within array bounds"
    case invalidArrayIndex = "array index is not a integer number"
    case objectKeyAlreadyExists = "cannot insert because object attribute already exists"
    case nonMatchingDataType = "the data type of value of the value does not match with expected data type that is required from query method"
    case nonNestableRootType = "root data type is neither array or object and cannot transverse"
    case nonNestedParent = "intermediate parent is a leaf node and non-nested. Cannot transverse further"
    case emptyQueryPath = "query path cannot be empty at this query usage"
    case captureUnknownElement = "the path cannot be end with a intermediate representer token"
    case cannotFindElement = "unable to find any element that matches the given path pattern"
    case other = "something went wrong. Target element cannot be found"
    
    /// Provide string representation of error.
    public func describe() -> String {
        return "[\(self)] \(rawValue)"
    }
}

public class ErrorInfo {
    public var errorCode: ErrorCode
    public var failedIndex: Int
    public var path: String
    
    internal init(_ errorCode: ErrorCode, _ failedIndex: Int, _ path: String) {
        self.errorCode = errorCode
        self.failedIndex = failedIndex
        self.path = path
    }
    
    public func explain() -> String {
        if path.count > 0 {
            return "[\(errorCode)] occurred on query path (\(path))\n\tAt attribute index \(failedIndex)\n\tReason: \(errorCode.rawValue)"
        }
        return "[\(errorCode)] occurred on root node itself\n\tReason: \(errorCode.rawValue)"
    }
}


public class JSONChild : JSONBlock {
    /// Name attribute of this element in the parent object.
    public var key = ""
    
    /// Index of this element in the parent array.
    public var index = -1
    
    internal func setKey(_ newKey: String) -> JSONChild {
        key = newKey
        return self
    }
    
    internal func setIndex(_ newIndex: Int) -> JSONChild {
        index = newIndex
        return self
    }
}

public class JSONBlock {
    
    private var base: Base = Base()
    
    private static let INVALID_START_CHARACTER_ERROR = "[JSONPond] the first character of given json content is neither starts with '{' or '['. Make sure the given content is valid JSON"
    private static let INVALID_BUFFER_INITIALIZATION = "[JSONPond] instance has not properly initialized. Problem had occured when assigning input data buffer which occur when the provider callback given on .init(provider:) gives nil or when exception thrown within provider callback itself. Check the result given by by provider callback to resolve the issue."
    
    /// Provide UTF string to read JSON content.
    public init(_ jsonString: String) {
        base.jsonText = jsonString
        switch (base.jsonText.first) {
        case "{": base.contentType = "object"
        case "[": base.contentType = "array"
        default:
            print(JSONBlock.INVALID_START_CHARACTER_ERROR)
            base.contentType = "string"
        }
        base.jsonData = UnsafeRawBufferPointer(start: base.jsonText.withUTF8({$0}).baseAddress, count: base.jsonText.count)
        base.identifyStringDelimiter(jsonString)
    }
    
    /// Provide buffer pointer to the JSON content bytes.
    public init(_ jsonBufferPointer: UnsafeRawBufferPointer) {
        base.jsonData = jsonBufferPointer
        switch(base.jsonData.first) {
        case 123: base.contentType = "object"
        case 91: base.contentType = "array"
        default:
            print(JSONBlock.INVALID_START_CHARACTER_ERROR)
            base.contentType = "string"
        }
    }
    
    /// Provide Data that contain JSON data
    public init (_ data: Data) {
        let buffer = data.withUnsafeBytes({$0})
        base.jsonData = buffer
        switch(base.jsonData.first) {
        case 123: base.contentType = "object"
        case 91: base.contentType = "array"
        default:
            print(JSONBlock.INVALID_START_CHARACTER_ERROR)
            base.contentType = "string"
        }
    }
    
//    /// Provide mirror callback to recieve UnsafeRawBufferPointer instance.
//    public init(_ provider:  ((UnsafeRawBufferPointer?) throws -> UnsafeRawBufferPointer?) throws -> UnsafeRawBufferPointer?) {
//        guard let buffer = try? provider({$0}) else {
//            print(JSONBlock.INVALID_BUFFER_INITIALIZATION)
//            base.contentType = "string"
//            return
//        }
//        base.jsonData = buffer
//        switch(base.jsonData.first) {
//        case 123: base.contentType = "object"
//        case 91: base.contentType = "array"
//        default:
//            print(JSONBlock.INVALID_START_CHARACTER_ERROR)
//            base.contentType = "string"
//        }
//    }
//
//    /// Provide mirror callback to receive UnsafeRawBufferPointer instance.
//    public init(_ provider:  ((UnsafeRawBufferPointer?)  -> UnsafeRawBufferPointer?) -> UnsafeRawBufferPointer?) {
//        guard let buffer = provider({$0}) else {
//            print(JSONBlock.INVALID_BUFFER_INITIALIZATION)
//            base.contentType = "string"
//            return
//        }
//        base.jsonData = buffer
//        switch(base.jsonData.first) {
//        case 123: base.contentType = "object"
//        case 91: base.contentType = "array"
//        default:
//            print(JSONBlock.INVALID_START_CHARACTER_ERROR)
//            base.contentType = "string"
//        }
//    }
    
//    public init(_ data: Data) {
//        let buffer = data.withUnsafeBytes({$0})
//        base.jsonData = buffer
//        switch(base.jsonData.first) {
//            case 123: base.contentType = "object"
//            case 91: base.contentType = "array"
//            default:
//                print(JSONBlock.INVALID_START_CHARACTER_ERROR)
//                base.contentType = "string"
//        }
//    }
    
    // ======= PRIVATE INITIALIZERS =====
    internal init(_ json: String, _ type: String, _ parent: Base? = nil) {
        if let parent {
            if parent.isBubbling {
                base.isBubbling = parent.errorHandler != nil
                base.errorHandler = parent.errorHandler
            }
        }
        
        base.jsonText = json
        base.contentType = type
        if base.contentType == "object" {
            base.identifyStringDelimiter(json)
            base.jsonData = UnsafeRawBufferPointer(start: base.jsonText.withUTF8({$0}).baseAddress, count: base.jsonText.count)
        }
    }
    
    
    internal init(_ json: [UInt8], _ type: String, _ parent: Base? = nil) {
        if let parent {
            if parent.isBubbling {
                base.isBubbling = parent.errorHandler != nil
                base.errorHandler = parent.errorHandler
            }
        }

        base.jsonDataMemoryHolder = json
        base.jsonText = ""
        base.contentType = type
        base.jsonData = base.jsonDataMemoryHolder.withUnsafeBytes({$0})
    }
    
    /// Set token to represent intermediate paths.
    /// Intermediate token capture zero or more dynamic intermediate paths. Default token is ???.
    public func setIntermediateGroupToken (_ representer: String) -> JSONBlock {
        if Int(representer) != nil {
            print("[JSONPond] intermediate represent strictly cannot be a number!")
            return self
        }
        base.intermediateSymbol = Array(representer.utf8)
        return self
    }

    /// Temporary make the next query string to be split by the character given. Useful in case of encountering object attribute containing dot notation in their names.
    public func splitQuery(by: Character) -> JSONBlock {
        base.pathSplitter = by
        return self
    }
    
    /// Get string value in the given path.
    public func string(_ path: String? = nil) -> String? {
        return base.getField(path, "string", { $0.string })
    }
    
    /// Get number value in the given path. Note that double instance is given even if
    /// number is a whole integer type number.
    public func number(_ path:String? = nil, ignoreType: Bool = false) -> Double? {
        return base.getField(path, "number", { Double($0.string) }, ignoreType: ignoreType)
    }
    
    /// Check if the element in the given addressed path represent a null value.
    public func isNull(_ path:String? = nil) -> Bool? {
        guard let type = path == nil ? base.contentType: base.decodeData(path!)?.type else {
            return nil
        }
        return type == "null"
    }
    
    /// Get JSON object in the given path. Activate ignoreType to parse JSON representable string if possible.
    public func objectEntry(_ path:String? = nil, ignoreType: Bool = false) -> JSONBlock? {
        if path == nil {
            if base.contentType == "object" {
                return self
            } else if ignoreType && base.contentType == "string" {
                let element = JSONBlock(base.jsonText, "object", base)
                if base.isBubbling {
                    element.base.isBubbling = true
                    element.base.errorHandler = base.errorHandler
                }
                return element
            }
            if base.errorHandler != nil {
                base.errorHandler!(ErrorInfo(ErrorCode.nonMatchingDataType, -1, ""))
                base.errorHandler = nil
            }
            return nil
        }
        let element = base.getField(path, "object", {
            // have to make sure value is string and not bytes...
            if ignoreType && $0.memoryHolder.count == 0 {
                return JSONBlock($0.string, "object", base)
            }
            return JSONBlock($0.memoryHolder, "object", base)
        }, ignoreType: ignoreType)
        if base.isBubbling {
            element?.base.isBubbling = true
            element?.base.errorHandler = base.errorHandler
        }
        return element
    }
    
    /// Get boolean value in the given path.
    public func bool(_ path: String? = nil, ignoreType: Bool = false) -> Bool? {
        return base.getField(path, "boolean", { $0.string == "true" }, ignoreType: ignoreType)
    }
    
    /// Get collection of items either from array or object. Gives array of [JSONChild] which each has property index and key which either has a value based on parent is a object or an array.
    public func collection(_ path: String? = nil, ignoreType: Bool = false) -> [JSONChild]? {
        guard let data = base.decodeData(path ?? "",
         copyCollectionData: true) else {
            return nil
        }
        if ignoreType && data.type == "string"{
            return JSONBlock(data.value.string).collection()
        }
        if data.type != "CODE_COLLECTION" {
            if base.errorHandler != nil {
                base.errorHandler!(ErrorInfo(
                    ErrorCode.nonMatchingDataType,
                    (path?.split(separator: base.pathSplitter).count ?? 0) - 1,
                    path ?? ""
                ))
                base.errorHandler = nil
            }
            return nil
        }
        return data.value.children
    }
    
    /// Check if attribute or element exists in given address path.
    public func isExist(
        _ path:String) -> Bool {
        return base.decodeData(path) != nil
    }
    
    /// Gives the current instance optionally if the given path exist otherwise return null.
    public func isExistThen(_ path:String) -> JSONBlock? {
        return base.decodeData(path) != nil ? self : nil
    }

    /// Read JSON element without type constraints.
    /// Similar to calling string(), array(), objectEntry() .etc but without knowing the data type
    /// of queried value. Returns castable `Any` value along with data type
    public func any(_ path: String) -> (value: Any, type: JSONType)? {
        guard let (value, type) = base.decodeData(path) else { return nil }
        if type == "object" {
            return (JSONBlock(value.memoryHolder, "object"), JSONType("object"))
        }
        return (base.resolveValue(value.string, value.memoryHolder, type), JSONType(type))
    }
    
    /// Get the data type of the value held by the content of this node.
    public func type() -> JSONType {
        return JSONType(base.contentType)
    }

    /// write JSON content from scratch recursively. use mapOf and listOf() to write object and array content respectively.
    public static func write(_ jsonData: Any, prettify: Bool = true) -> JSONBlock {
        let generatedBytes = Base.serializeToBytes(jsonData, 0, prettify ? 4 : 0, 34)
        if generatedBytes.first == 34 {
            return JSONBlock(String(
                generatedBytes.map({Character(UnicodeScalar($0))})
            ), "string")
        }
        let type = (jsonData as? [String: Any]) != nil ? "object" : "array"
        return JSONBlock(generatedBytes, type)
    }

    /// Attach a query fail listener to the next read or write query. Listener will be removed after single use.
    /// Bubbling enable inline generated instances to inherit this error handler.
    public func onQueryFail(_ handler: @escaping (ErrorInfo) -> Void, bubbling: Bool = false) -> JSONBlock {
        base.errorHandler = handler
        base.isBubbling = bubbling
        return self
    }

    @discardableResult
    /// Update the given given query path.
    public func replace(_ path: String, _ data: Any?, multiple: Bool = false) -> JSONBlock {
        base.write(path, data, writeMode: .onlyUpdate, multiple)
        if base.errorInfo != nil {
            base.errorHandler?(ErrorInfo(base.errorInfo!.code, base.errorInfo!.occurredQueryIndex, path))
            base.errorHandler = nil
        }
        return self
    }
    
    @discardableResult
    /// Insert an element to the given query path. Last segment of the path should address to attribute name / array index to insert on objects / arrays.
    public func insert(_ path: String, _ data: Any?, multiple: Bool = false) -> JSONBlock {
        base.write(path, data, writeMode: .onlyInsert, multiple)
        if base.errorInfo != nil {
            base.errorHandler?(ErrorInfo(base.errorInfo!.code, base.errorInfo!.occurredQueryIndex, path))
            base.errorHandler = nil
        }
        return self
    }
        
    @discardableResult
    /// Update or insert data to node of the given query path.
    public func upsert(_ path: String, _ data: Any?, multiple: Bool = false) -> JSONBlock {
        base.write(path, data, writeMode: .upsert, multiple)
        if base.errorInfo != nil {
            base.errorHandler?(ErrorInfo(base.errorInfo!.code, base.errorInfo!.occurredQueryIndex, path))
            base.errorHandler = nil
        }
        return self
    }
    
    @discardableResult
    /// delete path if exists. Return if delete successfully or not.
    public func delete(_ path: String, multiple: Bool = false) -> JSONBlock {
        base.write(path, 0, writeMode: .delete, multiple)
        if base.errorInfo != nil {
            base.errorHandler?(ErrorInfo(base.errorInfo!.code, base.errorInfo!.occurredQueryIndex, path))
            base.errorHandler = nil
        }
        return self
    }
    
    /// Returns the content data as [UInt8], map function parameter function optionally use to map the result with generic type.
    public func bytes<R>(_ mapFunction: ([UInt8]) -> R = {$0}) -> R {
        return mapFunction(Array(base.jsonData))
    }

    /// Convert the selected element content to representable `String`.
    public func stringify(_ path: String, tabSize: Int = 3) -> String? {
        guard let result =  base.decodeData(path)
        else { return nil }
        
        return result.type == "object" || result.type == "array" ? base.prettifyContent(result.value.memoryHolder.withUnsafeBytes({$0}), tabSize) : result.value.string
    }
    
    /// Convert the selected element content to representable `String`.
    public func stringify(tabSize: Int = 3) -> String {
        return base.contentType == "object" || base.contentType == "array" ? base.prettifyContent(base.jsonData, tabSize) : base.jsonText
    }
    
    /// Get the natural value of JSON node. Elements expressed in associated Swift type except
    /// for null represented in `.Constants.NULL` based on their data type. Both array and
    /// object are represented by `Array` and `Dictionary` respectively and their subElements are
    /// parsed recursively until to singular values.
        public func parse() -> Any {
        if base.contentType == "object" || base.contentType == "array" {
            var iterator = PeekIterator(base.jsonData)
            return base.getStructuredData(&iterator, firstCharacter: iterator.next()).value.tree
        }
        return base.resolveValue(base.jsonText, base.jsonDataMemoryHolder, base.contentType)
    }
    
    /// Get natural value of an element for given path with data type. Similar to `parse`.
    public func parseWithType(_ path: String) -> (value: Any,type: JSONType)? {
        base.extractInnerContent = true
        guard let (value, type) = base.decodeData(path) else { return nil }
        base.extractInnerContent = false
        if (type == "object" || type == "array") {
            return (value.tree, JSONType(type))
        }
        return (base.resolveValue(value.string, value.memoryHolder, type), JSONType(type))
    }
    
    /// Get the natural value of JSON node. Elements expressed in associated Swift type except
    /// for null represented in `.Constants.NULL` based on their data type. Both array and
    /// object are represented by `Array` and `Dictionary` respectively and their subElements are
    /// parsed recursively until to singular values.
    public func parse(_ path: String) -> Any? {
        base.extractInnerContent = true
        guard let (value, type) = base.decodeData(path) else { return nil }
        base.extractInnerContent = false
        if type == "object" || type == "array" {
            return value.tree
        }
        return base.resolveValue(value.string, value.memoryHolder, type)
    }
    
    /// Capture the node addressed by the given path.
    public func capture(_ path: String) -> JSONBlock? {
        guard let result = base.decodeData(path) else { return nil }
        let element =  result.type == "object" || result.type == "array" ?
        JSONBlock(result.value.memoryHolder, result.type) : JSONBlock(result.value.string, result.type)
        if base.isBubbling {
            element.base.isBubbling = true
            element.base.errorHandler = base.errorHandler
        }
        return element
    }
    
    /// Get collection all values that matches the given path. typeOf parameter to include type constraint else items are not type filtered.
    public func all(_ path: String, typeOf: JSONType? = nil) -> [JSONBlock] {
        return base.decodeData(path, grabAllPaths: true, multiCollectionTypeConstraint: typeOf?.rawValue)?.value.array ?? []
    }
}
