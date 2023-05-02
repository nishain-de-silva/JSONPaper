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

public class JSONBlock {
    public class JSONChild : JSONBlock {
        /// Name attribute of this element in the parent object.
        public var key = ""
        
        /// Index of this element in the parent array.
        public var index = -1
        
        fileprivate func setKey(_ newKey: String) -> JSONChild {
            key = newKey
            return self
        }
        
        fileprivate func setIndex(_ newIndex: Int) -> JSONChild {
            index = newIndex
            return self
        }
    }
    
    private static let INVALID_START_CHARACTER_ERROR = "[JSONPond] the first character of given json content is neither starts with '{' or '['. Make sure the given content is valid JSON"
    private static let INVALID_BUFFER_INITIALIZATION = "[JSONPond] instance has not properly initialized. Problem had occured when assigning input data buffer which occur when the provider callback given on .init(provider:) gives nil or when exception thrown within provider callback itself. Check the result given by by provider callback to resolve the issue."
    
    public class ErrorInfo {
        public var errorCode: ErrorCode
        public var failedIndex: Int
        public var path: String
        
        fileprivate init(_ errorCode: ErrorCode, _ failedIndex: Int, _ path: String) {
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
    
    private var jsonText: String = ""
    private var jsonData: UnsafeRawBufferPointer = UnsafeRawBufferPointer.init(start: nil, count: 0)
    private var jsonDataMemoryHolder: [UInt8] = []
    private var contentType:String
    private var extractInnerContent = false
    private var intermediateSymbol: [UInt8] = [63, 63, 63]
    private var errorHandler: ((ErrorInfo) -> Void)? = nil
    private var errorInfo: (code: ErrorCode, occurredQueryIndex: Int)? = nil
    private var pathSpliter: Character = "."
    private var isBubbling: Bool = false
    private var QUOTATION: UInt8 = 34
    
    private class ValueStore {
        var string: String = ""
        var memoryHolder: [UInt8] = []
        
        var array: [JSONBlock] = []
        var children: [JSONChild] = []
        var tree: Any = []
        
        init(_ input: String) {
            string = input
        }
        
        init(_ data: [UInt8]) {
            memoryHolder = data
        }
        
        init(_ text: String, _ data: [UInt8]) {
            string = text
            memoryHolder = data
        }
        
        init(arrayData: [JSONBlock]) {
            array = arrayData
        }
        
        init(childData: [JSONChild]) {
            children = childData
        }
        
        init(parsedData: Any) {
            tree = parsedData
        }
    }
    
    /// Provide UTF string to read JSON content.
    public init(_ jsonString: String) {
        jsonText = jsonString
        switch (jsonText.first) {
        case "{": contentType = "object"
        case "[": contentType = "array"
        default:
            print(JSONBlock.INVALID_START_CHARACTER_ERROR)
            contentType = "string"
        }
        jsonData = UnsafeRawBufferPointer(start: jsonText.withUTF8({$0}).baseAddress, count: jsonText.count)
        identifyStringDelimter(jsonString)
    }
    
    /// Provide buffer pointer to the JSON content bytes.
    public init(_ jsonBufferPointer: UnsafeRawBufferPointer) {
        jsonData = jsonBufferPointer
        switch(jsonData.first) {
        case 123: contentType = "object"
        case 91: contentType = "array"
        default:
            print(JSONBlock.INVALID_START_CHARACTER_ERROR)
            contentType = "string"
        }
    }
    
    /// Provide mirror callback to recieve UnsafeRawBufferPointer instance.
    public init(_ provider:  ((UnsafeRawBufferPointer?) throws -> UnsafeRawBufferPointer?) throws -> UnsafeRawBufferPointer?) {
        guard let buffer = try? provider({$0}) else {
            print(JSONBlock.INVALID_BUFFER_INITIALIZATION)
            contentType = "string"
            return
        }
        jsonData = buffer
        switch(jsonData.first) {
        case 123: contentType = "object"
        case 91: contentType = "array"
        default:
            print(JSONBlock.INVALID_START_CHARACTER_ERROR)
            contentType = "string"
        }
    }
    
    /// Provide mirror callback to receive UnsafeRawBufferPointer instance.
    public init(_ provider:  ((UnsafeRawBufferPointer?)  -> UnsafeRawBufferPointer?) -> UnsafeRawBufferPointer?) {
        guard let buffer = provider({$0}) else {
            print(JSONBlock.INVALID_BUFFER_INITIALIZATION)
            contentType = "string"
            return
        }
        jsonData = buffer
        switch(jsonData.first) {
        case 123: contentType = "object"
        case 91: contentType = "array"
        default:
            print(JSONBlock.INVALID_START_CHARACTER_ERROR)
            contentType = "string"
        }
    }
    
    // ======= PRIVATE INITIALIZERS =====
    fileprivate init(_ json: String, _ type: String) {
        jsonText = json
        contentType = type
        if contentType == "object" {
            identifyStringDelimter(json)
            jsonData = UnsafeRawBufferPointer(start: jsonText.withUTF8({$0}).baseAddress, count: jsonText.count)
        }
    }
    
    
    fileprivate init(_ json: [UInt8], _ type: String) {
        jsonDataMemoryHolder = json
        jsonText = ""
        contentType = type
        jsonData = jsonDataMemoryHolder.withUnsafeBytes({$0})
    }
    
    
    /// Set token to represent intermediate paths.
    /// Intermediate token capture zero or more dynamic intermediate paths. Default token is ???.
    public func setIntermediateToken (_ representer: String) -> JSONBlock {
        if Int(representer) != nil {
            print("[JSONPond] intermediate represent strictly cannot be a number!")
            return self
        }
        intermediateSymbol = Array(representer.utf8)
        return self
    }

    /// Temporary make the next query string to be split by the character given. Useful in case of encountering object attribute containing dot notation in their names.
    public func splitQuery(by: Character) -> JSONBlock {
        pathSpliter = by
        return self
    }
    
    
    private func getField <T>(_ path: String?, _ fieldName: String, _ mapper: (ValueStore) -> T?, ignoreType:Bool = false, similarKeyMatch: Bool) -> T? {
        guard let (data, type) = path == nil ? (ValueStore(jsonText, jsonDataMemoryHolder), contentType) : decodeData(path!, ignoreCaseAndSpecialCharacters: similarKeyMatch) else { return nil; }
        if (!ignoreType && type != fieldName) || (ignoreType && type != fieldName && type != "string") {
            if errorHandler != nil {
                errorHandler!(ErrorInfo(
                    ErrorCode.nonMatchingDataType,
                    (path?.split(separator: pathSpliter).count ?? 0) - 1,
                    path ?? ""
                ))
                errorHandler = nil
            }
            return nil
        }
        return mapper(data)
    }
    
    /// Get string value in the given path.
    public func string(_ path: String? = nil, similarKeyMatch: Bool = false) -> String? {
        return getField(path, "string", { $0.string }, similarKeyMatch: similarKeyMatch)
    }
    
    /// Get number value in the given path. Note that double instance is given even if
    /// number is a whole integer type number.
    public func number(_ path:String? = nil, ignoreType: Bool = false, similarKeyMatch: Bool = false) -> Double? {
        return getField(path, "number", { Double($0.string) }, ignoreType: ignoreType, similarKeyMatch: similarKeyMatch)
    }
    
    /// Check if the element in the given addressed path represent a null value.
    public func isNull(_ path:String? = nil, similarKeyMatch: Bool = false) -> Bool? {
        guard let type = path == nil ? contentType: decodeData(path!, ignoreCaseAndSpecialCharacters: similarKeyMatch)?.type else {
            return nil
        }
        return type == "null"
    }
    
    /// Get object in the given path. Activate ignoreType to parse string as json object.
    public func objectEntry(_ path:String? = nil, ignoreType: Bool = false, similarKeyMatch: Bool = false) -> JSONBlock? {
        if path == nil {
            if contentType == "object" {
                return self
            } else if ignoreType && contentType == "string" {
                let element = JSONBlock(jsonText, "object")
                if isBubbling {
                    element.isBubbling = true
                    element.errorHandler = errorHandler
                }
                return element
            }
            if errorHandler != nil {
                errorHandler!(ErrorInfo(ErrorCode.nonMatchingDataType, -1, ""))
                errorHandler = nil
            }
            return nil
        }
        let element = getField(path, "object", {
            // have to make sure value is string and not bytes...
            if ignoreType && $0.memoryHolder.count == 0 {
                return JSONBlock($0.string, "object")
            }
            return JSONBlock($0.memoryHolder, "object")
        }, ignoreType: ignoreType, similarKeyMatch: similarKeyMatch)
        if isBubbling {
            element?.isBubbling = true
            element?.errorHandler = errorHandler
        }
        return element
    }
    
    /// Get boolean value in the given path.
    public func bool(_ path: String? = nil, ignoreType: Bool = false, similarKeyMatch: Bool = false) -> Bool? {
        return getField(path, "boolean", { $0.string == "true" }, ignoreType: ignoreType, similarKeyMatch: similarKeyMatch)
    }
    
    
    /// Get collection of items either from array or object. Gives array of [JSONChild] which each has property index and key.
    public func collection(_ path: String? = nil, ignoreType: Bool = false, similarKeyMatch: Bool = false) -> [JSONChild]? {
        guard let data = decodeData(path ?? "", 
         copyCollectionData: true,
         ignoreCaseAndSpecialCharacters: similarKeyMatch) else {
            return nil
        }
        if ignoreType && data.type == "string"{
            return JSONBlock(data.value.string).collection()
        }
        if data.type != "CODE_COLLECTION" {
            if errorHandler != nil {
                errorHandler!(ErrorInfo(
                    ErrorCode.nonMatchingDataType,
                    (path?.split(separator: pathSpliter).count ?? 0) - 1,
                    path ?? ""
                ))
                errorHandler = nil
            }
            return nil
        }
        return data.value.children
    }
    
    /// Check if attribute or element exists in given address path.
    public func isExist(
        _ path:String,
        similarKeyMatch: Bool = false) -> Bool {
        return decodeData(path, ignoreCaseAndSpecialCharacters: similarKeyMatch) != nil
    }
    
    /// Gives the current instance optionally based on if given path exist.
    public func isExistThen(_ path:String, similarKeyMatch: Bool = false) -> JSONBlock? {
        return decodeData(path, ignoreCaseAndSpecialCharacters: similarKeyMatch) != nil ? self : nil
    }
    
    
    private func resolveValue(_ stringData: String, _ byteData: [UInt8], _ type: String) -> Any {
        switch(type) {
            case "number": return Double(stringData) ?? "#INVALID_NUMERIC"
            case "array": return JSONBlock(byteData, "array").collection()!
            case "boolean": return stringData == "true" ? true : false
            case "null": return Constants.NULL
            default: return stringData
        }
    }
    
    /// Read JSON element without type constraints.
    /// Similar to calling string(), array(), objectEntry() .etc but without knowing the data type
    /// of queried value. Returns castable any value along with data type
    public func any(_ path: String, similarKeyMatch: Bool = false) -> (value: Any, type: JSONType)? {
        guard let (value, type) = decodeData(path, ignoreCaseAndSpecialCharacters: similarKeyMatch) else { return nil }
        if type == "object" {
            return (JSONBlock(value.memoryHolder, "object"), JSONType("object"))
        }
        return (resolveValue(value.string, value.memoryHolder, type), JSONType(type))
    }
    
    /// Get the data type of the value held by the content of this node.
    public func type() -> JSONType {
        return JSONType(contentType)
    }
    
    private static func _serializeToBytes(_ node: Any?, _ index: Int, _ tabCount: Int, _ stringDelimiter: UInt8) -> [UInt8]  {
        if let node {
            guard let object = node as? [String: Any?] else {
                guard let array = node as? [Any?] else {
                    guard let string = node as? String else {
                        guard let boolean =  node as? Bool else {
                            guard let intNumber = node as? Int else {
                                guard let doubleNumber = node as? Double else {
                                    return [stringDelimiter, 35, 73, 78, 86, 65, 76, 73, 68, 95, 84, 89, 80, 69, stringDelimiter] // "#INVALID_TYPE"
                                }
                                return Array(String(doubleNumber).utf8)
                            }
                            return Array(String(intNumber).utf8)
                        }
                        return boolean ? [116, 114, 117, 101] : [102, 97, 108, 115, 101]
                    }
                    return [stringDelimiter] + Array(string.utf8) + [stringDelimiter]
                }
                let innerContent = array.map({_serializeToBytes($0, index + 1, tabCount, stringDelimiter)})
                if tabCount != 0 && innerContent.count != 0 {
                    let spacer: [UInt8] = Array(repeating: 32, count: (index + 1) * tabCount)
                    let endSpacer: [UInt8] = Array(repeating: 32, count: index * tabCount)
                    var data: [UInt8] = [91, 10]
                    let seperator: [UInt8] = [44, 10] + spacer
                    data.append(contentsOf: spacer)
                    data.append(contentsOf: innerContent.joined(separator: seperator))
                    data.append(10)
                    data.append(contentsOf: endSpacer)
                    data.append(93)
                    return data
                }
                return ([91] + innerContent.joined(separator: [44])) + [93]
            }
            let innerContent = object.map({(key, value) in
                (([stringDelimiter] + Array(key.utf8)) + (tabCount != 0 ? [stringDelimiter, 58, 32] : [stringDelimiter, 58])) + _serializeToBytes(value,index + 1 , tabCount, stringDelimiter)
            })
            if tabCount != 0 && innerContent.count != 0 {
                let spacer: [UInt8] = Array(repeating: 32, count: (index + 1) * tabCount)
                let endSpacer: [UInt8] = Array(repeating: 32, count: index * tabCount)
                var data: [UInt8] = [123, 10]
                let seperator: [UInt8] = [44, 10] + spacer
                data.append(contentsOf: spacer)
                data.append(contentsOf: innerContent.joined(separator: seperator))
                data.append(10)
                data.append(contentsOf: endSpacer)
                data.append(125)
                return data
            }
            return ([123] + (innerContent.joined(separator: [44]))) + [125]
        } else {
            return [110, 117, 108, 108]
        }
    }
    
    /// write JSON content from scratch recursively. use mapOf and listOf() to write object and array content respectively.
    public static func write(_ jsonData: Any, prettify: Bool = true) -> JSONBlock {
        let generatedBytes = _serializeToBytes(jsonData, 0, prettify ? 4 : 0, 34)
        if generatedBytes.first == 34 {
            return JSONBlock(String(
                generatedBytes.map({Character(UnicodeScalar($0))})
            ), "string")
        }
        let type = (jsonData as? [String: Any]) != nil ? "object" : "array"
        return JSONBlock(generatedBytes, type)
    }
    
    private func _continueCopyData(_ iterator: inout UnsafeRawBufferPointer.Iterator, _ data: inout [UInt8], _ dataToAdd: [UInt8], dataType: Int) {
        var shoudRecoverComma = false
        // 0 - object/array, string - 1, others - 3
        if dataType == 0 {
            var notationBalance = 1
            while true {
                guard let char = iterator.next() else { break }
                if char == 123 || char == 91 {
                    notationBalance += 1
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                }
                if notationBalance == 0 {
                    break
                }
            }
        } else if dataType == 1 {
            while true {
                guard let char = iterator.next() else { break }
                if char == QUOTATION {
                    break
                }
            }
        } else if dataType == 3 {
            while true {
                guard let char = iterator.next() else { break }
                if char == 44 {
                    shoudRecoverComma = true
                    break
                } else if char == 125 || char == 93 {
                    break
                }
            }
        }
        data += dataToAdd
        if shoudRecoverComma {
            data.append(44)
        }
        while true {
            guard let char = iterator.next() else { break }
            data.append(char)
        }
        jsonDataMemoryHolder = data
        jsonData = jsonDataMemoryHolder.withUnsafeBytes({$0})
    }
    
    
    private func _isLastCharacterOpenNode(_ data: inout [UInt8]) -> Bool {
        while true {
            if data.last == 10 || data.last == 32 {
                data.removeLast()
            } else {
                return data.last == 123 || data.last == 91
            }
        }
    }
    
    private enum UpdateMode {
        case upsert
        case onlyUpdate
        case onlyInsert
        case delete
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
    
    private func _deleteData(_ iterator: inout UnsafeRawBufferPointer.Iterator, _ copiedData: inout [UInt8], _ tabUnitCount: Int, _ prevNotationBalnce: Int, _ pathCount: Int) {
        var didRemovedFirstComma = false
        var isInQuotes = false
        var notationBalance = prevNotationBalnce
        var escapeCharacter = false
        
        while true {
            guard let char = copiedData.last else { break }
            if !escapeCharacter && char == QUOTATION {
                isInQuotes = !isInQuotes
            }
            if !isInQuotes {
                if (char == 123 || char == 91) {
                    break
                } else if char == 44 {
                    copiedData.removeLast()
                    didRemovedFirstComma = true
                    break
                }
            }
            copiedData.removeLast()
            
            if escapeCharacter {
                escapeCharacter = false
            } else if char == 92 {
                escapeCharacter = true
            }
        }
        
        escapeCharacter = false
        isInQuotes = false
        
        while true {
            guard let char = iterator.next() else { break }
            if !escapeCharacter && char == QUOTATION {
                isInQuotes = !isInQuotes
            }
            if !isInQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if notationBalance == (pathCount - 1) {
                        if tabUnitCount != 0 {
                            if didRemovedFirstComma {
                                copiedData.append(10)
                                copiedData.append(contentsOf: [UInt8](repeating: 32, count: (pathCount - 1) * tabUnitCount))
                            }
                        }
                        copiedData.append(char)
                        break
                    }
                }
            }
            if char == 44 && notationBalance == pathCount {
                if didRemovedFirstComma {
                    copiedData.append(44)
                }
                break
            }
            if escapeCharacter {
                escapeCharacter = false
            } else if char == 92 {
                escapeCharacter = true
            }
        }
        
        while true {
            guard let char = iterator.next() else { break }
            copiedData.append(char)
        }
        
        jsonDataMemoryHolder = copiedData
        jsonData = jsonDataMemoryHolder.withUnsafeBytes({$0})
    }
            
    private func _toNumber(_ bytes:[UInt8]) -> Int? {
        var ans: Int = 0
        var bytesCopy = bytes
        var isNegative = false
        if bytesCopy.first == 45 {
            isNegative = true
            bytesCopy.removeFirst()
        }
        for b in bytesCopy {
            if b < 48 || b > 57 {
                return nil
            }
            ans *= 10
            ans += Int(b - 48)
        }
        if isNegative {
            ans *= -1
        }
        return ans
    }
    
    private func _splitPath(_ path: String, makeIgnoreCases: Bool = false) -> [[UInt8]] {
        let paths: [[UInt8]]
        if makeIgnoreCases {
             paths = path.split(separator: pathSpliter).map({
                text in
                let utfArray = Array(text.utf8)
                if utfArray == intermediateSymbol {
                     return utfArray
                }
                var modifiedUtf: [UInt8] = []
                for char in utfArray {
                    if (char > 96 && char < 123)
                        || (char > 47 && char < 58) {
                        modifiedUtf.append(char)
                    } else if (char > 64 && char < 91) {
                        modifiedUtf.append(char + 32)
                    }
                }
                return modifiedUtf
            })
        } else {
            paths = path.split(separator: pathSpliter).map({Array($0.utf8)})
        }
        if pathSpliter != "." {
            pathSpliter = "."
        }
        return paths
    }
    
    /// Attach a query fail listener to the next read or write query. Listener will be removed after single use.
    /// bubbling enable inline child element to inherit this error handler enabling fail invoked on child nodes captured by given error handler.
    public func onQueryFail(_ handler: @escaping (ErrorInfo) -> Void, bubbling: Bool = false) -> JSONBlock {
        errorHandler = handler
        isBubbling = bubbling
        return self
    }
    
    private func _addData(_ isInObject: Bool, _ dataToAdd: Any, _ iterator: inout UnsafeRawBufferPointer.Iterator, _ copiedBytes: inout [UInt8], _ tabUnitCount: Int, paths: [[UInt8]], isIntermediateAdd: Bool = false) -> (ErrorCode, Int)? {
        if !isIntermediateAdd && !_isLastCharacterOpenNode(&copiedBytes) {
            copiedBytes.append(44)
        }
        if tabUnitCount != 0 {
            copiedBytes.append(10)
            copiedBytes.append(contentsOf: [UInt8] (repeating: 32, count: (paths.count) * tabUnitCount))
        }
        if isInObject {
            copiedBytes.append(QUOTATION)
            copiedBytes.append(contentsOf: paths[paths.count - 1])
            let endKeyPhrase: [UInt8] = tabUnitCount == 0 ? [QUOTATION, 58] : [QUOTATION, 58, 32]
            copiedBytes.append(contentsOf: endKeyPhrase)
        }
        
        var bytesToAdd = JSONBlock._serializeToBytes(dataToAdd, paths.count, tabUnitCount, QUOTATION)
        
        if !isIntermediateAdd {
            if tabUnitCount != 0 {
                bytesToAdd.append(10)
                bytesToAdd.append(contentsOf: [UInt8] (repeating: 32, count: (paths.count - 1) * tabUnitCount))
            }
            bytesToAdd.append(isInObject ? 125 : 93)
        } else {
            var trialBytes: [UInt8] = []
            // this was due to rare case when pushing to an empty array when push index is 0
            while true {
                guard let char = iterator.next() else { break }
                trialBytes.append(char)
                if char != 32 && char != 10 {
                    if char != 93 {
                        bytesToAdd.append(44)
                    } else if tabUnitCount != 0 {
                        bytesToAdd.append(10)
                        bytesToAdd.append(contentsOf: [UInt8] (repeating: 32, count: (paths.count - 1) * tabUnitCount))
                    }
                    break
                }
            }
            bytesToAdd.append(contentsOf: trialBytes)
        }
        _continueCopyData(&iterator, &copiedBytes, bytesToAdd, dataType: 4)
        return nil
    }

    @discardableResult
    /// Update the given given query path.
    public func replace(_ path: String, _ data: Any) -> JSONBlock {
        errorInfo = _write(path, data, writeMode: .onlyUpdate)
        if let errorInfo {
            errorHandler?(ErrorInfo(errorInfo.code, errorInfo.occurredQueryIndex, path))
            errorHandler = nil
        }
        return self
    }
    
    @discardableResult
    /// Insert an element to the given query path. Last segment of the path can be attribute name to insert or update else and index if handling arrays.
    public func push(_ path: String, _ data: Any) -> JSONBlock {
        errorInfo = _write(path, data, writeMode: .onlyInsert)
        if let errorInfo {
            errorHandler?(ErrorInfo(errorInfo.code, errorInfo.occurredQueryIndex, path))
            errorHandler = nil
        }
        return self
    }
        
    @discardableResult
    /// Update or insert data to node of the given query path.
    public func replaceOrPush(_ path: String, _ data: Any) -> JSONBlock {
        errorInfo = _write(path, data, writeMode: .upsert)
        if let errorInfo {
            errorHandler?(ErrorInfo(errorInfo.code, errorInfo.occurredQueryIndex, path))
            errorHandler = nil
        }
        return self
    }
    
    @discardableResult
    /// delete path if exists. Return if delete successfully or not.
    public func delete(_ path: String) -> JSONBlock {
        errorInfo = _write(path, 0, writeMode: .delete)
        if let errorInfo {
            errorHandler?(ErrorInfo(errorInfo.code, errorInfo.occurredQueryIndex, path))
            errorHandler = nil
        }
        return self
    }
    
    /// Returns the content data as [UInt8], map function parameter function optionally use to map the result with generic type.
    public func bytes<R>(_ mapFunction: ([UInt8]) -> R = {$0}) -> R {
        return mapFunction(Array(jsonData))
    }
        
    private func _write(_ path: String, _ data: Any, writeMode: UpdateMode) -> (ErrorCode, Int)? {
        if contentType != "object" && contentType != "array" {
            return (ErrorCode.nonNestableRootType, 0)
        }
        var tabUnitCount = 0
        if jsonData[1] == 10 {
            while (tabUnitCount + 2) < jsonData.count {
                if jsonData[tabUnitCount + 2] == 32 {
                    tabUnitCount += 1
                } else { break }
            }
        }
        var isQuotes = false
        var isGrabbingKey = false
        var grabbedKey: [UInt8] = []
        var isEscaping = false
        var notationBalance = 0
        var processedindex = 0
        let paths:[[UInt8]] = _splitPath(path)
        var copiedBytes: [UInt8] = []
        var searchValue = 0
        var iterator = jsonData.makeIterator()
        
        if paths.count == 0 {
            return (ErrorCode.emptyQueryPath, -1)
        }
        while true {
            guard let char = iterator.next() else { break }
            if !isQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                    if searchValue == 1 {
                        if writeMode == .onlyInsert {
                            return (ErrorCode.objectKeyAlreadyExists, processedindex - 1)
                        }
                        let bytesToAdd = JSONBlock._serializeToBytes(data, paths.count, tabUnitCount, QUOTATION)
                        _continueCopyData(&iterator, &copiedBytes, bytesToAdd, dataType: 0)
                        return nil
                    } else if char == 91 && (processedindex + 1) == notationBalance {
                        guard let parsedInt = _toNumber(paths[processedindex]) else {
                            return (ErrorCode.invalidArrayIndex, processedindex)
                        }
                        searchValue = 0
                        if _iterateArrayWrite(&iterator, elementIndex: parsedInt, &copiedBytes) {
                            processedindex += 1
                            if processedindex == paths.count {
                                searchValue = 1
                                if writeMode == .delete {
                                    _deleteData(&iterator, &copiedBytes, tabUnitCount,notationBalance ,paths.count)
                                    return nil
                                } else if writeMode == .onlyInsert {
                                    return _addData(false, data, &iterator, &copiedBytes, tabUnitCount, paths: paths, isIntermediateAdd: true)
                                }
                            } else {
                                searchValue = 2
                            }
                        } else if processedindex < (paths.count - 1) {
                            return (ErrorCode.arrayIndexNotFound, processedindex)
                        } else if processedindex == (paths.count - 1) {
                            if writeMode == .upsert || writeMode == .onlyInsert {
                                return _addData(false, data, &iterator, &copiedBytes, tabUnitCount, paths: paths)
                            } else {
                                return (ErrorCode.arrayIndexNotFound, processedindex)
                            }
                        }
                        continue
                    }
                    else if searchValue != 0 {
                        searchValue = 0
                    }
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if processedindex >= notationBalance {
                        if notationBalance + 1 == paths.count && (writeMode == .upsert || writeMode == .onlyInsert) {
                            return _addData(char == 125, data, &iterator, &copiedBytes, tabUnitCount, paths: paths)
                        }
                        return (char == 125 ? ErrorCode.objectKeyNotFound : ErrorCode.arrayIndexNotFound, notationBalance)
                    }
                } else if char == 58 && (processedindex + 1) == notationBalance {
                    if paths[processedindex] == grabbedKey {
                        processedindex += 1
                        searchValue = 2
                        if processedindex == paths.count {
                            searchValue = 1
                            if writeMode == .delete {
                                _deleteData(&iterator, &copiedBytes, tabUnitCount,notationBalance ,paths.count)
                                return nil
                            }
                        }
                    }
                } else if searchValue > 0 && ((char >= 48 && char <= 57) || char == 45
                || char == 116 || char == 102
                || char == 110) {
                    if searchValue == 2 {
                        return (ErrorCode.nonNestedParent, processedindex - 1)
                    }
                    if writeMode == .onlyInsert {
                        return (ErrorCode.objectKeyAlreadyExists, processedindex - 1)
                    }
                    let bytesToAdd = JSONBlock._serializeToBytes(data, paths.count, tabUnitCount, QUOTATION)
                    _continueCopyData(&iterator, &copiedBytes, bytesToAdd, dataType: 3)
                    return nil
                }
            }
            if !isEscaping && char == QUOTATION {
                isQuotes = !isQuotes
                if searchValue > 0 {
                    if searchValue == 2 {
                        return (ErrorCode.nonNestedParent, processedindex - 1)
                    }
                    if writeMode == .onlyInsert {
                        return (ErrorCode.objectKeyAlreadyExists, processedindex - 1)
                    }

                    let bytesToAdd = JSONBlock._serializeToBytes(data, paths.count, tabUnitCount, QUOTATION)
                    _continueCopyData(&iterator, &copiedBytes, bytesToAdd, dataType: 1)
                    return nil
                } else if (processedindex + 1) == notationBalance {
                    isGrabbingKey = isQuotes
                    if isGrabbingKey {
                        grabbedKey = []
                    }
                }
            } else if isGrabbingKey {
                grabbedKey.append(char)
            }
            if isEscaping {
                isEscaping = false
            } else if char == 92 {
                isEscaping = true
            }
            copiedBytes.append(char)
        }
        return (ErrorCode.other, processedindex)
    }
    
    private func _prettyifyContent(_ originalContent: UnsafeRawBufferPointer) -> String {
        var presentation: [UInt8] = []
        var notationBalance = 0
        var isEscaping = false
        var isQuotes = false
        if originalContent[1] == 10 { // already being pretty...
            return String(originalContent.map({Character(UnicodeScalar($0))}))
        }
        for char in originalContent {
            if !isEscaping && char == QUOTATION {
                isQuotes = !isQuotes
            } else if !isQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                    presentation.append(char)
                    presentation.append(10)
                    presentation.append(contentsOf: [UInt8] (repeating: 32, count: notationBalance * 3))
                    continue
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    presentation.append(10)
                    presentation.append(contentsOf: [UInt8] (repeating: 32, count: notationBalance * 3))
                } else if char == 44 {
                    presentation.append(char)
                    presentation.append(10)
                    presentation.append(contentsOf: [UInt8] (repeating: 32, count: notationBalance * 3))
                    continue
                } else if char == 58 {
                    presentation.append(char)
                    presentation.append(32)
                    continue
                }
            }

            if isEscaping {
                isEscaping = false
            } else if char == 92 {
                isEscaping = true
            }
            presentation.append(char)
        }
        return String(presentation.map({Character(UnicodeScalar($0))}))
    }
    /// Convert the selected element content to representable string.
    public func stringify(_ path: String, similarKeyMatch: Bool = false) -> String? {
        guard let result =  decodeData(path, ignoreCaseAndSpecialCharacters: similarKeyMatch)
        else { return nil }
        
        return result.type == "object" || result.type == "array" ? _prettyifyContent(result.value.memoryHolder.withUnsafeBytes({$0})) : result.value.string
    }
    
    /// Convert the selected element content to representable string.
    public func stringify() -> String {
        return contentType == "object" || contentType == "array" ? _prettyifyContent(jsonData) : jsonText
    }
    
    /// Get the natural value of JSON node. Elements expressed in associated swift type except
    /// for null represented in `.Constants.NULL` based on their data type. Both array and
    /// object are represented by dictionary and array respectively and their subelements are
    /// parsed recursively until to singular values.
        public func parse() -> Any {
        if contentType == "object" || contentType == "array" {
            var iterator = jsonData.makeIterator()
            return _getStructuredData(&iterator, firstCharacter: iterator.next()!).value.tree
        }
        return resolveValue(jsonText, jsonDataMemoryHolder, contentType)
    }
    
    /// Get natural value of an element for given path with data type. Similar to parse(path:).
    public func parseWithType(_ path: String, similarKeyMatch: Bool = false) -> (value: Any,type: JSONType)? {
        extractInnerContent = true
        guard let (value, type) = decodeData(path, ignoreCaseAndSpecialCharacters: similarKeyMatch) else { return nil }
        extractInnerContent = false
        if (type == "object" || type == "array") {
            return (value.tree, JSONType(type))
        }
        return (resolveValue(value.string, value.memoryHolder, type), JSONType(type))
    }
    
    /// Get the natural value of JSON node. Elements expressed in associated swift type except
    /// for null represented in `.Constants.NULL` based on their data type. Both array and
    /// object are represented by dictionary and array respectively and their subelements are
    /// parsed recursively until to singular values.
    public func parse(_ path: String, similarKeyMatch: Bool = false) -> Any? {
        extractInnerContent = true
        guard let (value, type) = decodeData(path, ignoreCaseAndSpecialCharacters: similarKeyMatch) else { return nil }
        extractInnerContent = false
        if type == "object" || type == "array" {
            return value.tree
        }
        return resolveValue(value.string, value.memoryHolder, type)
    }
    
    /// Capture the node addressed by the given path.
    public func capture(_ path: String, similarKeyMatch: Bool = false) -> JSONBlock? {
        guard let result = decodeData(path, ignoreCaseAndSpecialCharacters: similarKeyMatch) else { return nil }
        let element =  result.type == "object" || result.type == "array" ?
        JSONBlock(result.value.memoryHolder, result.type) : JSONBlock(result.value.string, result.type)
        if isBubbling {
            element.isBubbling = true
            element.errorHandler = errorHandler
        }
        return element
    }
    
    ///Gell collection all values on that matches the given path.
    public func all(_ path: String, similarKeyMatch: Bool = false) -> [JSONBlock] {
        return decodeData(path, ignoreCaseAndSpecialCharacters: similarKeyMatch, grabAllPaths: true)?.value.array ?? []
    }
    
    private func decodeData(_ inputPath:String, copyCollectionData: Bool = false, ignoreCaseAndSpecialCharacters: Bool, grabAllPaths: Bool = false) -> (value: ValueStore, type: String)? {
        let results = exploreData(inputPath, copyCollectionData, ignoreCaseAndSpecialCharacters, grabAllPaths)
        if let errorInfo {
            errorHandler?(ErrorInfo(errorInfo.code, errorInfo.occurredQueryIndex, inputPath))
            errorHandler = nil
        }
        return results
    }
    
    private func _asString(_ bytes: [UInt8]) -> String {
        return String(bytes.map({Character(UnicodeScalar($0))}))
    }
    
    private func _trimSpace(_ input: String) -> String {
        var output = input
        while(output.last!.isWhitespace) {
            output.removeLast()
        }
        return output
    }
    
    private func parseSingularValue(_ input: String) -> Any {
        if input.first == "t" {
            return true
        } else if input.first == "f" {
            return false
        } else if input.first == "n" {
            return Constants.NULL
        } else {
            return Double(input) ?? "#INVALID_NUMERIC"
        }
    }
    private class CollectionHolder {
        var type: String
        var objectCollection: [String: Any]
        var arrayCollection: [Any]
        var reservedObjectKey = ""
        
        init(isObject: Bool) {
            type = isObject ? "object" : "array"
            objectCollection = [:]
            arrayCollection = []
        }
        
        func assignChildToObject(_ child: CollectionHolder) {
            objectCollection[reservedObjectKey] = child.type == "object" ? child.objectCollection : child.arrayCollection
        }
        
        func appendChildToArray(_ child: CollectionHolder) {
            arrayCollection.append(child.type == "object" ? child.objectCollection : child.arrayCollection)
        }

    }
    
    private func _getStructuredData(_ iterator: inout UnsafeRawBufferPointer.Iterator, firstCharacter: UInt8) -> (value: ValueStore, type: String) {
        var stack: [CollectionHolder] = []
        var isInQuotes = false
        var grabbedKey = ""
        var isGrabbingText = false
        var grabbedText = ""
        var notationBalance = 1
        var shouldProccessObjectValue = false
        var escapeCharacter = false
        
        if firstCharacter == 123 {
            stack.append(CollectionHolder(isObject: true))
        } else {
            stack.append(CollectionHolder(isObject: false))
        }
        while true {
            guard let char: UInt8 = iterator.next() else { break }
            if !isInQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                    if stack.last!.type == "object" {
                        stack.last!.reservedObjectKey = grabbedKey
                    }
                    stack.append(CollectionHolder(isObject: char == 123))
                    shouldProccessObjectValue = false
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if isGrabbingText {
                        if stack.last!.type == "object" {
                            stack.last!.objectCollection[grabbedKey] = parseSingularValue(_trimSpace(grabbedText))
                        } else {
                            stack.last!.arrayCollection.append(parseSingularValue(_trimSpace(grabbedText)))
                        }
                        isGrabbingText = false
                    }
                    if notationBalance == 0 {
                        return stack.first!.type == "object" ? (ValueStore(parsedData: stack.last!.objectCollection), "object") : (ValueStore(parsedData: stack.last!.arrayCollection), "array")
                    }
                    shouldProccessObjectValue = false
                    let child = stack.removeLast()
                    if stack.last!.type == "object" {
                        stack.last!.assignChildToObject(child)
                    } else {
                        stack.last!.appendChildToArray(child)
                    }
                } else if char == 58 {
                    shouldProccessObjectValue = true
                    grabbedKey = grabbedText
                } else if !isGrabbingText && ((char >= 48 && char <= 57) || char == 45
                    || char == 116 || char == 102
                    || char == 110) {
                    grabbedText = ""
                    isGrabbingText = true
                } else if char == 44 && isGrabbingText {
                    isGrabbingText = false
                    if stack.last!.type == "object" {
                        stack.last!.objectCollection[grabbedKey] = parseSingularValue(_trimSpace(grabbedText))
                    } else {
                        stack.last!.arrayCollection.append(parseSingularValue(_trimSpace(grabbedText)))
                    }
                    shouldProccessObjectValue = false
                }
            }
            if !escapeCharacter && char == QUOTATION {
                isInQuotes = !isInQuotes
                isGrabbingText = isInQuotes
                if isGrabbingText {
                    grabbedText = ""
                } else {
                    if stack.last!.type == "object" {
                        if shouldProccessObjectValue {
                            stack.last!.objectCollection[grabbedKey] = grabbedText
                        }
                    } else {
                        stack.last!.arrayCollection.append(grabbedText)
                    }
                    shouldProccessObjectValue = false
                }
            } else if isGrabbingText {
                grabbedText.append(Character(UnicodeScalar(char)))
            }
            if escapeCharacter {
                escapeCharacter = false
            } else if char == 92 {
                escapeCharacter = true
            }
        }
        return (ValueStore(parsedData: []), firstCharacter == 123 ? "object" : "array")
    }
    
    private func _iterateArray(_ iterator: inout UnsafeRawBufferPointer.Iterator, elementIndex: Int) -> Bool {
        var notationBalance = 1
        var escapeChracter = false
        var isQuotes = false
        var cursorIndex = 0
        
        if elementIndex == 0 { return true }
        while true {
            guard let char = iterator.next() else { break }
            if !escapeChracter && char == QUOTATION {
                isQuotes = !isQuotes
            }
            if !isQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if notationBalance == 0 {
                        return false
                    }
                } else if char == 44 && notationBalance == 1 {
                    cursorIndex += 1
                    if cursorIndex == elementIndex {
                        return true
                    }
                }
            }
            if escapeChracter {
                escapeChracter = false
            } else if char == 92 {
                escapeChracter = true
            }
        }
        return false
    }
    
    private func _iterateArrayWrite(_ iterator: inout UnsafeRawBufferPointer.Iterator, elementIndex: Int, _ copyingData: inout [UInt8]) -> Bool {
        var notationBalance = 1
        var escapeChracter = false
        var isQuotes = false
        var cursorIndex = 0
        
        copyingData.append(91)
        if elementIndex == 0 { return true }
        
        while true {
            guard let char = iterator.next() else { break }
            
            if !escapeChracter && char == QUOTATION {
                isQuotes = !isQuotes
            }
            if !isQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if notationBalance == 0 {
                        return false
                    }
                } else if char == 44 && notationBalance == 1 {
                    cursorIndex += 1
                    if cursorIndex == elementIndex {
                        copyingData.append(char)
                        return true
                    }
                }
            }
            if escapeChracter {
                escapeChracter = false
            } else if char == 92 {
                escapeChracter = true
            }
            copyingData.append(char)
        }
        return false
    }
    
    private func _grabData(_ copiedData: inout [UInt8], _ iterator: inout UnsafeRawBufferPointer.Iterator) {
        var notationBalance = 1
        var isQuotes = false
        var isEscape = false
        while true {
            guard let char = iterator.next() else { break }
            if !isEscape && char == QUOTATION {
                isQuotes = !isQuotes
            }
            if !isQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                }
                else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if notationBalance == 0 {
                        copiedData.append(char)
                        return
                    }
                }
                if char > 32 {
                    copiedData.append(char)
                }
            } else {
                copiedData.append(char)
            }
            if isEscape {
                isEscape = false
            } else if char == 92 {
                isEscape = true
            }
        }
    }
    
    private func _getObjectEntries(_ iterator: inout UnsafeRawBufferPointer.Iterator) -> [JSONChild] {
        var values: [JSONChild] = []
        var bytes: [UInt8] = []
        var text: String = ""
        var dataType = ""
        var isQuotes = false
        var grabbedKey = ""
        var isEscaping = false
        var shouldGrabItem = false
        while true {
            guard let char = iterator.next() else { break }
             if !isEscaping && char == QUOTATION {
                isQuotes = !isQuotes
                if isQuotes {
                    text = ""
                    continue
                } else {
                    if shouldGrabItem {
                        shouldGrabItem = false
                        values.append(JSONChild(text, "string").setKey(grabbedKey))
                    }
                }
            } else if !isQuotes {
                if char == 123 || char == 91 {
                    bytes = [char]
                    dataType = char == 123 ? "object" : "array"
                    _grabData(&bytes, &iterator)
                    values.append(JSONChild(bytes, dataType).setKey(grabbedKey))
                    shouldGrabItem = false
                    continue
                }
                if shouldGrabItem {
                    if let result = _getPrimitive(&iterator, char) {
                        values.append(JSONChild(result.value, result.dataType).setKey(grabbedKey))
                        shouldGrabItem = false
                        if result.didContainerClosed {
                            return values
                        }
                    }
                } else if char == 58 {
                    shouldGrabItem = true
                    grabbedKey = text
                    continue
                } else if char == 125 {
                    return values
                }
            } else {
                text.append(Character(UnicodeScalar(char)))
            }
            if isEscaping {
                isEscaping = false
            } else if char == 92 {
                isEscaping = true
            }
        }
        return values
    }

    
    private func _getArrayValues(_ iterator: inout UnsafeRawBufferPointer.Iterator) -> [JSONChild] {
        var values: [JSONChild] = []
        var bytes: [UInt8] = []
        var text: String = ""
        var dataType = ""
        var isQuotes = false
        var isEscaping = false
        var index = 0
        while true {
            guard let char = iterator.next() else { break }
            if !isEscaping && char == QUOTATION {
                isQuotes = !isQuotes
                if isQuotes {
                    text = ""
                    continue
                } else {
                    values.append(JSONChild(text, "string").setIndex(index))
                    index += 1
                }
            } else if !isQuotes {
                if char == 123 || char == 91 {
                    bytes = [char]
                    dataType = char == 123 ? "object" : "array"
                    _grabData(&bytes, &iterator)
                    values.append(JSONChild(bytes, dataType).setIndex(index))
                    index += 1
                    continue
                }
                if let result = _getPrimitive(&iterator, char) {
                    values.append(JSONChild(result.value, result.dataType).setIndex(index))
                    index += 1
                    if result.didContainerClosed {
                        return values
                    }
                } else if char == 93 {
                    return values
                }
                
            } else {
                text.append(Character(UnicodeScalar(char)))
            }
            if isEscaping {
                isEscaping = false
            } else if char == 92 {
                isEscaping = true
            }
        }
        return values
    }
    
    private func _getPrimitive(_ iterator: inout UnsafeRawBufferPointer.Iterator, _ firstCharacter: UInt8) -> (dataType: String, value: String, didContainerClosed: Bool)? {
        if firstCharacter == 116 {
            return ("boolean", "true", false)
        } else if firstCharacter == 102 {
            return ("boolean", "false", false)
        } else if firstCharacter == 110 {
            return ("null", "null", false)
        } else if (firstCharacter > 47 && firstCharacter < 58) || firstCharacter == 45 {
            var didContainerClosed = false
            var copiedNumber = "\(Character(UnicodeScalar(firstCharacter)))"
            while true {
                guard let num = iterator.next() else { break }
                if (num > 47 && num < 58) || num == 46 {
                    copiedNumber.append(Character(UnicodeScalar(num)))
                } else {
                    if num == 125 || num == 93 {
                        didContainerClosed = true
                    }
                    break
                }
            }
            return ("number", copiedNumber, didContainerClosed)
        }
        return nil
    }
    
    private func _singleItemList(_ source: JSONBlock) -> (ValueStore, String) {
        return (ValueStore(arrayData: [source]), "CODE_ALL")
    }
    
    private func exploreData(_ inputPath: String,
     _ copyCollectionData: Bool,
     _ ignoreCaseAndSpecialCharacters: Bool, _ grabAllPaths: Bool
        ) -> (value: ValueStore, type: String)? {
        errorInfo = nil
        if !(contentType == "object" || contentType == "array") {
            errorInfo = (ErrorCode.nonNestableRootType, 0)
            return nil
        }
        var paths:[[UInt8]] = _splitPath(inputPath, makeIgnoreCases: ignoreCaseAndSpecialCharacters)
        var processedPathIndex = 0
        var isNavigatingUnknownPath = false
        var advancedOffset = 0
        var traversalHistory: [(processedPathIndex: Int, advancedOffset: Int)] = []

        var isInQuotes = false
        var startSearchValue = false
        var isGrabbingText = false
        var grabbedText = ""
        var grabbedBytes: [UInt8] = []
        var grabbingKey:[UInt8] = []
        var needProcessKey = false
        var isGrabbingKey = false
    
        var notationBalance = 0
        var grabbingDataType: String = "string"
        var escapeCharacter: Bool = false
        var commonPathCollections: [JSONBlock] = []
        
        func restoreLastPointIfNeeded() -> Bool {
            if traversalHistory.count > 0 {
                (processedPathIndex, advancedOffset) =  traversalHistory[traversalHistory.count - 1]
                startSearchValue = false
                isNavigatingUnknownPath = true
                return true
            }
            return false
        }
        
        if paths.count == 0 && !copyCollectionData {
            errorInfo = (ErrorCode.emptyQueryPath, -1)
            return nil
        }
        if paths.last == intermediateSymbol {
            errorInfo = (ErrorCode.captureUnknownElement, paths.count - 1)
            return nil
        }
        var iterator = jsonData.makeIterator()
        while true {
            guard let char = iterator.next() else { break }
            // if within quotation ignore processing json literals...
            if !isInQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                    // if the last value of last key is object or array then start copy it
                    if processedPathIndex == paths.count {
                        if extractInnerContent {
                            return _getStructuredData(&iterator, firstCharacter: char)
                        }
                        if copyCollectionData {
                            if char == 123 {
                                return (ValueStore(childData: _getObjectEntries(&iterator)), "CODE_COLLECTION")
                            }
                            return (ValueStore(childData: _getArrayValues(&iterator)), "CODE_COLLECTION")
                        }
                        grabbedBytes = [char]
                        grabbingDataType = char == 123 ? "object" : "array"
                        _grabData(&grabbedBytes, &iterator)
                        if grabAllPaths {
                            if restoreLastPointIfNeeded() {
                                commonPathCollections.append(JSONBlock(grabbedBytes, grabbingDataType))
                                continue
                            }
                            return _singleItemList(JSONBlock(grabbedBytes, grabbingDataType))
                        }
                        return (ValueStore(grabbedBytes), grabbingDataType)
                    }
                    if paths[processedPathIndex] == intermediateSymbol {
                        isNavigatingUnknownPath = true
                        traversalHistory.append((processedPathIndex, advancedOffset))
                        paths.remove(at: processedPathIndex)
                    }
                    // initiate elements counting inside array on reaching open bracket...
                    if char == 91 && ((advancedOffset + 1) == notationBalance || isNavigatingUnknownPath) {
                        let parsedIndex = _toNumber(paths[processedPathIndex])
                        // occur when trying to access element of array with non-number index
                        if parsedIndex == nil {
                            if isNavigatingUnknownPath || restoreLastPointIfNeeded() {
                                continue
                            }
                            errorInfo = (ErrorCode.invalidArrayIndex, processedPathIndex)
                            return nil
                        }
                        if isNavigatingUnknownPath {
                            isNavigatingUnknownPath = false
                            advancedOffset = notationBalance - 1
                        }
                        if !_iterateArray(&iterator, elementIndex: parsedIndex!) {
                            if traversalHistory.count != 0 {
                                if traversalHistory.count != 1 {
                                    traversalHistory.removeLast()
                                    paths.insert(intermediateSymbol, at: processedPathIndex)
                                }
                                (processedPathIndex, advancedOffset) = traversalHistory[traversalHistory.count - 1]
                                isNavigatingUnknownPath = true
                                continue
                            }
                            errorInfo = (ErrorCode.arrayIndexNotFound, processedPathIndex)
                            return nil
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
                
                if char == 125 || char == 93 {
                    notationBalance -= 1
                    // occur after all element in foccused array or object is finished searching...
                    if notationBalance <= advancedOffset {
                        if traversalHistory.count != 0 {
                            if traversalHistory.last!.advancedOffset <= advancedOffset {
                                paths.insert(intermediateSymbol, at: traversalHistory.removeLast().processedPathIndex)
                                
                                if traversalHistory.count == 0 {
                                    if grabAllPaths {
                                        return (ValueStore(arrayData: commonPathCollections), "CODE_ALL")
                                    }
                                    errorInfo = (ErrorCode.cannotFindElement, notationBalance)
                                    return nil
                                }
                            }
                            (processedPathIndex, advancedOffset) = traversalHistory.last!
                            isNavigatingUnknownPath = true
                            continue
                        }
                        errorInfo = (char == 125 ? ErrorCode.objectKeyNotFound : ErrorCode.arrayIndexNotFound, notationBalance)
                        return nil
                        
                    }
                    
                    continue
                }
            }
            
            // ======== FINISHED HALDING JSON OPEN AND CLOSE NOTATION ==========
            if startSearchValue {
                if notationBalance == advancedOffset {
                    // ====== HANDLING GRABBING STRINGS =========
                    // ignore escaped double quotation characters inside string values...
                    if !escapeCharacter && char == QUOTATION {
                        isInQuotes = !isInQuotes
                        // if not the last processed value skip capturing value
                        if processedPathIndex != paths.count {
                            if restoreLastPointIfNeeded() {
                                continue
                            }
                            errorInfo = (ErrorCode.nonNestedParent, processedPathIndex - 1)
                            return nil
                        }
                        isGrabbingText = !isGrabbingText
                        if !isGrabbingText {
                            if grabAllPaths {
                                if restoreLastPointIfNeeded() {
                                    commonPathCollections.append(JSONBlock(grabbedText, "string"))
                                    continue
                                }
                                return  _singleItemList(JSONBlock(grabbedText, "string"))
                            }
                            return (ValueStore(grabbedText), "string")
                        } else {
                            grabbedText = ""
                        }
                        // used to copy values true, false, null and number
                    } else {
                        // ========== HANDLING GRABING NUMBERS, BOOLEANS AND NULL
                        if !isInQuotes && !isGrabbingText {
                            if let result = _getPrimitive(&iterator, char) {
                                if processedPathIndex != paths.count {
                                    if restoreLastPointIfNeeded() {
                                        continue
                                    }
                                    errorInfo = (ErrorCode.nonNestedParent, processedPathIndex - 1)
                                    return nil
                                }
                                if grabAllPaths {
                                    if restoreLastPointIfNeeded() {
                                        commonPathCollections.append(JSONBlock(result.value,  result.dataType))
                                        continue
                                    }
                                    return _singleItemList(JSONBlock(result.value, result.dataType))
                                }
                                return (ValueStore(result.value), result.dataType)
                            }
                        } else if isGrabbingText {
                            grabbedText.append(Character(UnicodeScalar(char)))
                        }
                    }
                } else if char == QUOTATION && !escapeCharacter {
                    isInQuotes = !isInQuotes
                }
                
                // ========= SECTION RESPONSIBLE HANDLING OBJECT KEY
            } else {
                if char == QUOTATION && !escapeCharacter {
                    isInQuotes = !isInQuotes
                    // grabbing the matching correct object key as given in path
                    if (advancedOffset + 1) == notationBalance || isNavigatingUnknownPath {
                        isGrabbingKey = isInQuotes
                        if isGrabbingKey {
                            grabbingKey = []
                        } else {
                            needProcessKey = true
                        }
                    }
                } else if isGrabbingKey {
                    if ignoreCaseAndSpecialCharacters {
                        if (char > 47 && char < 58) {
                            grabbingKey.append(char)
                        } else if (char > 64 && char < 91) {
                            grabbingKey.append(char + 32)
                        } else if (char > 96 && char < 123) {
                            grabbingKey.append(char)
                        }
                    } else {
                        grabbingKey.append(char)
                    }
                } else if needProcessKey && char == 58 {
                    needProcessKey = false
                    // if found start searching for object value for object key
                    if grabbingKey == paths[processedPathIndex] {
                        processedPathIndex += 1
                        advancedOffset += 1
                        startSearchValue = true
                        if isNavigatingUnknownPath {
                            isNavigatingUnknownPath = false
                            advancedOffset = notationBalance
                        }
                    }
                }
            }
            // handling escape characters at the end ...
            if escapeCharacter {
                escapeCharacter = false
            } else if char == 92 {
                escapeCharacter = true
            }
        }
        errorInfo = (ErrorCode.other, processedPathIndex)
        return nil
    }
    
    private func identifyStringDelimter(_ text: String) {
        for char in text {
            if char == "\"" || char == "'" {
                QUOTATION = char == "\"" ? 34 : 39
                break
            }
        }
    }
}
