/// JSONStore represenentation of Null
public enum Constants {
    case NULL
}

/// JSONStore represenentation of Null
public let Null = Constants.NULL

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

public class JSONEntity {
    private static let INVALID_START_CHARACTER_ERROR = "[JSONStore] the first character of given json content is neither starts with '{' or '['. Make sure the given content is valid JSON"
    private static let INVALID_BUFFER_INITIALIZATION = "[JSONStore] instance has not properly initialized. Problem had occured when assigning input data buffer which occur when the provider callback given on .init(provider:) gives nil or when exception thrown within provider callback itself. Check the result given by by provider callback to resolve the issue."
    
    private var jsonText: String = ""
    private var jsonData: UnsafeRawBufferPointer = UnsafeRawBufferPointer.init(start: nil, count: 0)
    private var jsonDataMemoryHolder: [UInt8] = []
    private var contentType:String
    private var copyArrayData:Bool = false
    private var copyObjectEntries:Bool = false
    private var extractInnerContent = false
    private var intermediateSymbol: [UInt8] = [63, 63, 63]
    private var errorHandler: (((ErrorCode, Int)) -> Void)? = nil
    private var errorInfo: (code: ErrorCode, occurredQueryIndex: Int)? = nil
    private var pathSpliter: Character = "."
    private var typeMismatchWarningCount = 0

    private class ValueStore {
        var string: String
        var bytes: UnsafeRawBufferPointer
        var memoryHolder: [UInt8] = []
        var entries: [(key: String, value: JSONEntity)]
        var array: [JSONEntity]
        var tree: any Collection
        
        init(_ input: String) {
            string = input
            bytes = UnsafeRawBufferPointer(start: nil, count: 0)
            entries = []
            array = []
            tree = []
        }
        
        init(_ data: [UInt8]) {
            memoryHolder = data
            bytes = memoryHolder.withUnsafeBytes({$0})
            string = ""
            entries = []
            array = []
            tree = []
            
        }
        
        init(_ text: String, _ data: UnsafeRawBufferPointer) {
            string = text
            bytes = data
            entries = []
            array = []
            tree = []
        }
        
        init(entriesData: [(String, JSONEntity)]) {
            string = ""
            bytes = UnsafeRawBufferPointer(start: nil, count: 0)
            entries = entriesData
            array = []
            tree = []
        }
        
        init(arrayData: [JSONEntity]) {
            string = ""
            bytes = UnsafeRawBufferPointer(start: nil, count: 0)
            entries = []
            array = arrayData
            tree = []
        }
        
        init(parsedData: any Collection) {
            string = ""
            bytes = UnsafeRawBufferPointer(start: nil, count: 0)
            entries = []
            array = []
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
            print(JSONEntity.INVALID_START_CHARACTER_ERROR)
            contentType = "string"
        }
        jsonData = UnsafeRawBufferPointer(start: jsonText.withUTF8({$0}).baseAddress, count: jsonText.count)
    }
    
    /// Provide buffer pointer to the JSON content bytes.
    public init(_ jsonBufferPointer: UnsafeRawBufferPointer) {
        jsonData = jsonBufferPointer
        switch(jsonData.first) {
        case 123: contentType = "object"
        case 91: contentType = "array"
        default:
            print(JSONEntity.INVALID_START_CHARACTER_ERROR)
            contentType = "string"
        }
    }
    
    /// Provide mirror callback to recieve UnsafeRawBufferPointer instance.
    public init(_ provider:  ((UnsafeRawBufferPointer?) throws -> UnsafeRawBufferPointer?) throws -> UnsafeRawBufferPointer?) {
        guard let buffer = try? provider({$0}) else {
            print(JSONEntity.INVALID_BUFFER_INITIALIZATION)
            contentType = "string"
            return
        }
        jsonData = buffer
        switch(jsonData.first) {
        case 123: contentType = "object"
        case 91: contentType = "array"
        default:
            print(JSONEntity.INVALID_START_CHARACTER_ERROR)
            contentType = "string"
        }
    }
    
    /// Provide mirror callback to recieve UnsafeRawBufferPointer instance.
    public init(_ provider:  ((UnsafeRawBufferPointer?)  -> UnsafeRawBufferPointer?) -> UnsafeRawBufferPointer?) {
        guard let buffer = provider({$0}) else {
            print(JSONEntity.INVALID_BUFFER_INITIALIZATION)
            contentType = "string"
            return
        }
        jsonData = buffer
        switch(jsonData.first) {
        case 123: contentType = "object"
        case 91: contentType = "array"
        default:
            print(JSONEntity.INVALID_START_CHARACTER_ERROR)
            contentType = "string"
        }
    }
    
    // ======= PRIVATE INTITIALIZERS =====
    private init(_ json: String, _ type: String) {
        jsonText = json
        contentType = type
        if contentType == "object" {
            jsonData = UnsafeRawBufferPointer(start: jsonText.withUTF8({$0}).baseAddress, count: jsonText.count)
        }
    }
    
    
    private init(_ json: [UInt8], _ type: String) {
        jsonDataMemoryHolder = json
        jsonText = ""
        contentType = type
        jsonData = jsonDataMemoryHolder.withUnsafeBytes({$0})
    }
    
    private init(_ json: UnsafeRawBufferPointer, _ type: String) {
        jsonText = ""
        contentType = type
        jsonData = json
    }
    
    /// Set token to represent intermediate paths.
    /// Intermediate token capture zero or more dynamic intermediate paths. Default token is ???.
    public func setIntermediateRepresentor (_ representer: String) -> JSONEntity {
        if Int(representer) != nil {
            print("[JSONStore] intermediate representer strictly cannot be a number!")
            return self
        }
        intermediateSymbol = Array(representer.utf8)
        return self
    }

    /// Tempolary make the next query string to be split by the character given. Useful in case of encountering object attribute containing dot notation in their names.
    public func splitQuery(by: Character) -> JSONEntity {
        pathSpliter = by
        return self
    }
    
    private func getField <T>(_ path: String?, _ fieldName: String, _ mapper: (ValueStore) -> T?, ignoreType:Bool = false) -> T? {
        guard let (data, type) = path == nil ? (ValueStore(jsonText, jsonData), contentType) : decodeData(path!) else { return nil; }
        if !ignoreType && type != fieldName {
            if typeMismatchWarningCount != 3 {
                print("[JSONStore] type constrained query expected \(fieldName) but \(type) type value was read instead therefore returned nil. This warning will not be shown after 3 times per instance")
                typeMismatchWarningCount += 1
            }
            return nil
        }
        return mapper(data)
    }
    
    /// Get string value in the given path.
    public func string(_ path:String? = nil) -> String? {
        return getField(path, "string", { $0.string })
    }
    
    /// Get number value in the given path. Note that double instance is given even if
    /// number is a whole integer type number.
    public func number(_ path:String? = nil, ignoreType: Bool = false) -> Double? {
        return getField(path, "number", { Double($0.string) }, ignoreType: ignoreType)
    }
    
    /// Check if the element in the given addressed path represent a null value.
    public func isNull(_ path:String? = nil) -> Bool? {
        guard let type = path == nil ? contentType: decodeData(path!)?.type else {
            return nil
        }
        return type == "null"
    }
    
    /// Get object in the given path. Activate ignoreType to parse string as json object.
    public func object(_ path:String? = nil, ignoreType: Bool = false) -> JSONEntity? {
        if path == nil { return self }
        return getField(path, "object", {
            ignoreType ? JSONEntity(replaceEscapedQuotations($0.string), "object") : JSONEntity($0.memoryHolder, "object")
        }, ignoreType: ignoreType)
    }
    
    /// Get boolean value in the given path.
    public func bool(_ path: String? = nil, ignoreType: Bool = false) -> Bool? {
        return getField(path, "boolean", { $0.string == "true" }, ignoreType: ignoreType)
    }
    
    /// Get collection of elements in an array found in given path. Activate ignoreType to parse addressed string to json array.
    public func array(_ path:String? = nil, ignoreType: Bool = false) -> [JSONEntity]? {
        if ignoreType {
            guard let arrayContent = getField(path, "string", { replaceEscapedQuotations($0.string) }, ignoreType: true) else { return nil }
            return JSONEntity(arrayContent).array()
        }
        copyArrayData = true
        let data = decodeData(path == nil ? "-1" : "\(path!).-1")
        if data?.type != "CODE_ARRAY" {
            copyArrayData = false
            return nil
        }
        copyArrayData = false
        return data?.value.array
    }
    
    /// Check if attribute or element exists in given address path.
    public func isExist(_ path:String) -> Bool {
        return decodeData(path) != nil
    }
    
    /// Check if attribute or element exists in given address path.
    public func isExist(_ path:String) -> JSONEntity? {
        return decodeData(path) != nil ? self : nil
    }
    
    /// Get array of key-value tuple of the object. The path must point to object type.
    public func entries(_ path: String? = nil) -> [(key: String, value: JSONEntity)]? {
        copyObjectEntries = true
        let data = decodeData(path == nil || path!.count == 0 ? "dummyAtr" : "\(path!)\(pathSpliter)dummyAtr")
        if data?.type != "CODE_ENTRIES" {
            copyObjectEntries = false
            return nil
        }
        copyObjectEntries = false
        return data?.value.entries
    }
    
    private func resolveValue(_ stringData: String, _ byteData: UnsafeRawBufferPointer, _ type: String, serialize: Bool = false) -> Any {
        switch(type) {
        case "number": return Double(stringData) ?? "#INVALID_NUMERIC"
        case "array": return JSONEntity(byteData, "array").array()!
        case "boolean": return stringData == "true" ? true : false
        case "null": return Constants.NULL
        default: return stringData
        }
    }
    
    /// Read JSON element without type constraints.
    /// Similar to calling string(), array(), object() .etc but without knowing the data type
    /// of queried value. Returns castable any value along with data type
    public func any(_ path: String) -> (value: Any, type: JSONType)? {
        guard let (value, type) = decodeData(path) else { return nil }
        if type == "object" {
            return (JSONEntity(value.memoryHolder, "object"), JSONType("object"))
        }
        return (resolveValue(value.string, value.bytes, type), JSONType(type))
    }
    
    /// Get the data type of the value held by the content of this node.
    public func type() -> JSONType {
        return JSONType(contentType)
    }
    
    private static func _serializeToBytes(_ node: Any, _ index: Int, _ tabCount: Int) -> [UInt8]  {
        guard let object = node as? [String: Any] else {
            guard let array = node as? [Any] else {
                guard let string = node as? String else {
                    guard let boolean =  node as? Bool else {
                        guard let intNumber = node as? Int else {
                            guard let doubleNumber = node as? Double else {
                                if node as? Constants == .NULL {
                                    return [110, 117, 108, 108]
                                }
                                return [34, 35, 73, 78, 86, 65, 76, 73, 68, 95, 84, 89, 80, 69, 34] // "#INVALID_TYPE"
                            }
                            return Array(String(doubleNumber).utf8)
                        }
                        return Array(String(intNumber).utf8)
                    }
                    return boolean ? [116, 114, 117, 101] : [102, 97, 108, 115, 101]
                }
                return [34] + Array(string.utf8) + [34]
            }
            let innerContent = array.map({_serializeToBytes($0, index + 1, tabCount)})
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
            (([34] + Array(key.utf8)) + (tabCount != 0 ? [34, 58, 32] : [34, 58])) + _serializeToBytes(value,index + 1 , tabCount)
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
    }
    
    public static func write(_ jsonData: Any, prettify: Bool = true) -> JSONEntity {
        let type = (jsonData as? [String: Any]) != nil ? "object" : "array"
        return JSONEntity(_serializeToBytes(jsonData, 0, prettify ? 4 : 0),type)
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
                if char == 34 {
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
        case arrayIndexNotFound = "cannot find indexed item within array bounds"
        case invalidArrayIndex = "array index is not a integer number"
        case objectKeyAlreadyExists = "cannot insert because object attribute already exists"
        case arrayIndexAlreadyExists = "cannot insert because array index is already exists"
        case nonNestableRootType = "root data type is neither array or object and cannot transverse"
        case nonNestedParent = "intermediate parent is a leaf node and non-nested. Cannot transverse further"
        case emptyQueryPath = "query path cannot be empty at this query usage"
        case indexGivenOnArrayAppend = "Do not define the index where the item should be added in insert operation, they are always added to end of the array"
        case unknownTargetOnQuery = "the path cannot be end with a intermediate representer"
        case other = "something went wrong. Element cannot be found"
        
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
            if !escapeCharacter && char == 34 {
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
            if !escapeCharacter && char == 34 {
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
    
    private func _splitPath(_ path: String) -> [[UInt8]] {
        let paths: [[UInt8]] =  path.split(separator: pathSpliter).map({Array($0.utf8)})
        if pathSpliter != "." {
            pathSpliter = "."
        }
        return paths
    }
    
    /// Attach a query fail listener to the next read or write query. Listener will be removed after single use.
    public func onQueryFail(_ handler: @escaping ((error: ErrorCode, querySegmentIndex: Int)) -> Void) -> JSONEntity {
        errorHandler = handler
        return self
    }
    
    private func _addData(_ isInObject: Bool, _ dataToAdd: Any, _ iterator: inout UnsafeRawBufferPointer.Iterator, _ copiedBytes: inout [UInt8], _ tabUnitCount: Int, paths: [[UInt8]], _ preventAppendToArray: Bool) -> (ErrorCode, Int)? {
        if !_isLastCharacterOpenNode(&copiedBytes) {
            copiedBytes.append(44)
        }
        if tabUnitCount != 0 {
            copiedBytes.append(10)
            copiedBytes.append(contentsOf: [UInt8] (repeating: 32, count: (paths.count) * tabUnitCount))
        }
        if isInObject {
            copiedBytes.append(34)
            copiedBytes.append(contentsOf: paths[paths.count - 1])
            let endKeyPhrase: [UInt8] = tabUnitCount == 0 ? [34, 58] : [34, 58, 32]
            copiedBytes.append(contentsOf: endKeyPhrase)
        } else if preventAppendToArray {
            return (ErrorCode.indexGivenOnArrayAppend, paths.count - 1)
        }
        
        var bytesToAdd = JSONEntity._serializeToBytes(dataToAdd, paths.count, tabUnitCount)
        if tabUnitCount != 0 {
            bytesToAdd.append(10)
            bytesToAdd.append(contentsOf: [UInt8] (repeating: 32, count: (paths.count - 1) * tabUnitCount))
        }
        bytesToAdd.append(isInObject ? 125 : 93)
        _continueCopyData(&iterator, &copiedBytes, bytesToAdd, dataType: 4)
        return nil
    }

    /// Update the given given query path.
    public func update(_ path: String, _ data: Any) -> JSONEntity {
        errorInfo = _write(path, data, writeMode: .onlyUpdate)
        if errorInfo != nil {
            errorHandler?(errorInfo!)
            errorHandler = nil
        }
        return self
    }
    
    /// Insert an element to the given query path. If the last segment of the path is an array then the element will be added to the array else if it's a nonexistent key then the key attribute will be added to the object.
    public func insert(_ path: String, _ data: Any) -> JSONEntity {
        errorInfo = _write(path, data, writeMode: .onlyInsert)
        if errorInfo != nil {
            errorHandler?(errorInfo!)
            errorHandler = nil
        }
        return self
    }
        
    /// Update or insert data to node of the given query path.
    public func upsert(_ path: String, _ data: Any) -> JSONEntity {
        errorInfo = _write(path, data, writeMode: .upsert)
        if errorInfo != nil {
            errorHandler?(errorInfo!)
            errorHandler = nil
        }
        return self
    }
    
    /// delete path if exists. Return if delete successfull or not.
    public func delete(_ path: String) -> JSONEntity {
        errorInfo = _write(path, 0, writeMode: .delete)
        if errorInfo != nil {
            errorHandler?(errorInfo!)
            errorHandler = nil
        }
        return self
    }
    
    /// Returns the content data as [UInt8], map function parameter function optionally use to map the result with generic type.
    public func toBytes<R>(_ mapFunction: ([UInt8]) -> R = {$0}) -> R {
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
        var paths:[[UInt8]] = _splitPath(path)
        var isCountArray = false
        var pathIndexCursor = -1
        var pathElementindex = 0
        var copiedBytes: [UInt8] = []
        var searchValue = 0
        var iterator = jsonData.makeIterator()
        var shouldAppendToArray = false
        
        // speacial case scenario if appending to root array...
        if paths.count == 0 {
            if contentType == "array" && writeMode == .onlyInsert {
                paths.append([45, 49])
                shouldAppendToArray = true
            } else {
                return (ErrorCode.emptyQueryPath, -1)
            }
        }
        while true {
            guard let char = iterator.next() else { break }
            if !isQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                    if isCountArray {
                        if pathIndexCursor != pathElementindex {
                            copiedBytes.append(char)
                            continue
                        } else {
                            isCountArray = false
                        }
                    }
                    if searchValue == 1 {
                        if writeMode == .onlyInsert {
                            if char == 91 {
                                isCountArray = true
                                searchValue = 0
                                pathElementindex = -1
                                pathIndexCursor = 0
                                paths.append([45, 49])
                                copiedBytes.append(char)
                                shouldAppendToArray = true
                                continue
                            }
                            return (isCountArray ? ErrorCode.arrayIndexAlreadyExists : ErrorCode.objectKeyAlreadyExists, processedindex - 1)
                        }
                        let bytesToAdd = JSONEntity._serializeToBytes(data, paths.count, tabUnitCount)
                        _continueCopyData(&iterator, &copiedBytes, bytesToAdd, dataType: 0)
                        return nil
                    } else if char == 91 && (processedindex + 1) == notationBalance {
                        isCountArray = true
                        guard let parsedInt = _toNumber(paths[processedindex]) else {
                            return (ErrorCode.invalidArrayIndex, processedindex)
                        }
                        searchValue = 0
                        pathElementindex = parsedInt
                        pathIndexCursor = 0
                        if pathElementindex == 0 {
                            processedindex += 1
                            searchValue = 2
                            if processedindex == paths.count {
                                searchValue = 1
                                if writeMode == .delete {
                                    copiedBytes.append(char)
                                    _deleteData(&iterator, &copiedBytes, tabUnitCount,notationBalance ,paths.count)
                                    return nil
                                }
                            }
                        }
                    }
                    else if searchValue != 0{
                        searchValue = 0
                    }
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if processedindex == notationBalance {
                        if processedindex + 1 == paths.count && (writeMode == .upsert || writeMode == .onlyInsert) {
                            return _addData(char == 125, data, &iterator, &copiedBytes, tabUnitCount, paths: paths, char == 93 && writeMode == .onlyInsert && !shouldAppendToArray)
                        }
                        return (char == 125 ? ErrorCode.objectKeyNotFound : ErrorCode.arrayIndexNotFound, processedindex)
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
                        return (isCountArray ? ErrorCode.arrayIndexAlreadyExists : ErrorCode.objectKeyAlreadyExists, processedindex - 1)
                    }
                    let bytesToAdd = JSONEntity._serializeToBytes(data, paths.count, tabUnitCount)
                    _continueCopyData(&iterator, &copiedBytes, bytesToAdd, dataType: 3)
                    return nil
                } else if char == 44 {
                    if isCountArray && (processedindex + 1) == notationBalance {
                        pathIndexCursor += 1
                        if pathElementindex == pathIndexCursor {
                            processedindex += 1
                            searchValue = 2
                            if processedindex == paths.count {
                                searchValue = 1
                                if writeMode == .delete {
                                    copiedBytes.append(char)
                                    _deleteData(&iterator, &copiedBytes, tabUnitCount,notationBalance ,paths.count)
                                    return nil
                                }
                            }
                        }
                    }
                }
            }
            if !isEscaping && char == 34 {
                isQuotes = !isQuotes
                if searchValue > 0 {
                    if searchValue == 2 {
                        return (ErrorCode.nonNestedParent, processedindex - 1)
                    }
                    if writeMode == .onlyInsert {
                        return (isCountArray ? ErrorCode.arrayIndexAlreadyExists : ErrorCode.objectKeyAlreadyExists, paths.count - 2)
                    }

                    let bytesToAdd = JSONEntity._serializeToBytes(data, paths.count, tabUnitCount)
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
    
    /// Convert the selected element content to representable string.
    public func stringify(_ path: String) -> String? {
        guard let result =  decodeData(path)
        else { return nil }
        
        return result.value.bytes.count == 0 ? result.value.string : 
        String(result.value.bytes.map({
                Character(UnicodeScalar($0))
        }))   
    }
    
    /// Convert the selected element content to representable string.
    public func stringify() -> String {
        return jsonData.count == 0 ? jsonText : String(jsonData.map({Character(UnicodeScalar($0))}))
    }
    
    /// Get the natural value of JSON node. Elements expressed in associated swift type except
    /// for null represented in `.Constants.NULL` based on their data type. Both array and
    /// object are represented by dictionary and array respectively and their subelements are
    /// parsed recursively until to singular values.
        public func parse() -> Any {
        if contentType == "object" || contentType == "array" {
            var iterator = jsonData.makeIterator()
            return fowardToExtract(&iterator, firstCharacter: iterator.next()!).value.tree
        }
        return resolveValue(jsonText, jsonData, contentType)
    }
    
    /// Get natural value of an element for given path with data type. Similar to parse(path:).
    public func parseWithType(_ path: String) -> (value: Any,type: JSONType)? {
        extractInnerContent = true
        guard let (value, type) = decodeData(path) else { return nil }
        extractInnerContent = false
        if (type == "object" || type == "array") {
            return (value.tree, JSONType(type))
        }
        return (resolveValue(value.string, value.bytes, type), JSONType(type))
    }
    
    /// Get the natural value of JSON node. Elements expressed in associated swift type except
    /// for null represented in `.Constants.NULL` based on their data type. Both array and
    /// object are represented by dictionary and array respectively and their subelements are
    /// parsed recursively until to singular values.
    public func parse(_ path: String) -> Any? {
        extractInnerContent = true
        guard let (value, type) = decodeData(path) else { return nil }
        extractInnerContent = false
        if (type == "object" || type == "array") && value.string == "CODE_parse" {
            return value.tree
        }
        return resolveValue(value.string, value.bytes, type)
    }
    
    /// Capture the node addressed by the given path.
    public func take(_ path: String) -> JSONEntity? {
        guard let result = decodeData(path) else { return nil }
        return result.value.bytes.count == 0 ? 
            JSONEntity(result.value.string, result.type) :
            JSONEntity(result.value.memoryHolder, result.type)
    }
    
    private func decodeData(_ inputPath:String) -> (value: ValueStore, type: String)? {
        let results = exploreData(inputPath, copyArrayData: copyArrayData, copyObjectEntries: copyObjectEntries)
        if errorInfo != nil {
            errorHandler?(errorInfo!)
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
    class CollectionHolder {
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
    
    private func fowardToExtract(_ iterator: inout UnsafeRawBufferPointer.Iterator, firstCharacter: UInt8) -> (value: ValueStore, type: String) {
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
            if !escapeCharacter && char == 34 {
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
    
    private func exploreData(_ inputPath:String, copyArrayData: Bool, copyObjectEntries: Bool
        ) -> (value: ValueStore, type: String)? {
        errorInfo = nil
        if !(contentType == "object" || contentType == "array") {
            errorInfo = (ErrorCode.nonNestableRootType, 0)
            return nil
        }
        var paths:[[UInt8]] = _splitPath(inputPath)
        var processedPathIndex = 0
        var isNavigatingUnknownPath = false
        var advancedOffset = 0
        var tranversalHistory: [(processedPathIndex: Int, advancedOffset: Int)] = []

        var isInQuotes = false
        var startSearchValue = false
        var isGrabbingText = false
        var grabbedText = ""
        var grabbedBytes: [UInt8] = []
        var grabbingKey:[UInt8] = []
        var needProccessKey = false
        var isGrabbingNotation = false
        var isGrabbingKey = false
        var isCountArray = false
        var isGrabbingArrayValues = false
        
        var elementIndexCursor = -1 // the count variable when iterating array
        var pathArrayIndex = -1 // the array index of given on path
        var notationBalance = 0
        var grabbingDataType: String = "string"
        var possibleType: String = ""
        var escapeCharacter: Bool = false
        
        var arrayValues: [JSONEntity] = []
        var objectEntries : [(key: String, value: JSONEntity)] = []

        if paths.count == 0 {
            errorInfo = (ErrorCode.emptyQueryPath, -1)
            return nil
        }
        if paths.last == intermediateSymbol {
            errorInfo = (ErrorCode.unknownTargetOnQuery, paths.count - 1)
            return nil
        }
        var iterator = jsonData.makeIterator()
        while true {
            guard let char = iterator.next() else { break }
            // if within quotation ignore processing json literals...
            if !isInQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                    if isCountArray && !isGrabbingArrayValues {
                        // ignore processing if element in not matching the array index except when grabbing all elements on array
                        if elementIndexCursor != pathArrayIndex {

                            // start grabbing array/object array elements on isGrabbingArrayValues mode
                            if isGrabbingArrayValues {
                                if notationBalance == advancedOffset + 2 {
                                    grabbedBytes = []
                                    grabbingDataType = char == 123 ? "object" : "array"
                                }
                                grabbedBytes.append(char)
                            }
                            continue
                        }
                        // if element found for matched index stop array searching ..
                        processedPathIndex += 1
                        advancedOffset += 1
                        isCountArray = false
                    }
                    // if the last value of last key is object or array then start copy it
                    if (processedPathIndex == paths.count || isGrabbingArrayValues) && !isGrabbingNotation {
                        if extractInnerContent {
                            return fowardToExtract(&iterator, firstCharacter: char)
                        }
                        grabbedBytes = []
                        isGrabbingNotation = true
                        grabbingDataType = char == 123 ? "object" : "array"
                    }
                    
                    // continue copying object/arrray inner characters...
                    if isGrabbingNotation {
                        grabbedBytes.append(char)
                        continue
                    }
                    
                    // intiate elements counting inside array on reaching open bracket...
                    if char == 91 && !isCountArray && ((advancedOffset + 1) == notationBalance || isNavigatingUnknownPath) {
                        let parsedIndex = _toNumber(paths[processedPathIndex])
                        // occur when trying to access element of array with non-number index
                        if parsedIndex == nil {
                           if paths[processedPathIndex] == intermediateSymbol {
                                paths.remove(at: processedPathIndex)
                                isNavigatingUnknownPath = true
                                tranversalHistory.append((processedPathIndex, advancedOffset))
                                continue
                           } else if isNavigatingUnknownPath { continue }
                            errorInfo = (ErrorCode.invalidArrayIndex, processedPathIndex)
                            return nil
                        }
                        if isNavigatingUnknownPath {
                            isNavigatingUnknownPath = false
                            advancedOffset = notationBalance - 1
                        }
                        isCountArray = true
                        pathArrayIndex = parsedIndex!
                        elementIndexCursor = 0
                        startSearchValue = true
                        
                        // start to copy all element of array given on last path index
                        if copyArrayData && (processedPathIndex + 1) == paths.count {
                            isGrabbingArrayValues = true
                        }
                    } else {
                        // move to next nest object and start looking attribute key on next nested object...
                        startSearchValue = false
                        if paths[processedPathIndex] == intermediateSymbol {
                            isNavigatingUnknownPath = true
                            tranversalHistory.append((processedPathIndex, advancedOffset))
                            paths.remove(at: processedPathIndex)
                        }
                    }
                    continue
                }
                
                if char == 125 || char == 93 {
                    notationBalance -= 1
                    
                    // if a primitive value is in proccess copying then return copied value
                    if isGrabbingText {
                        // when finished copy last primitive value on copyObjectEntries mode. Need to make sure the parent container notation is an object
                        if copyObjectEntries && char == 125 {
                            objectEntries.append((_asString(grabbingKey), JSONEntity(_trimSpace(grabbedText), grabbingDataType)))
                            return (ValueStore(entriesData: objectEntries), "CODE_ENTRIES")
                        } else if isGrabbingArrayValues {
                            // append the pending grabbing text
                            arrayValues.append(JSONEntity(_trimSpace(grabbedText), grabbingDataType))
                        } else {
                            return (ValueStore(_trimSpace(grabbedText)), grabbingDataType)
                        }
                    }
                    if isGrabbingNotation {
                        grabbedBytes.append(char)
                    }
                    
                    // occur after all element in foccused array or object is finished searching...
                    if notationBalance == advancedOffset {
                        if isCountArray && char == 93 {
                            // occur when when not matching element is found for given array index and array finished iterating...
                            if tranversalHistory.count != 0 && !(isGrabbingArrayValues && (processedPathIndex + 1) == paths.count){
                                if tranversalHistory.count != 1 {
                                    tranversalHistory.removeLast()
                                    paths.insert(intermediateSymbol, at: processedPathIndex)
                                }
                                (processedPathIndex, advancedOffset) = tranversalHistory[tranversalHistory.count - 1]
                                isNavigatingUnknownPath = true
                                isCountArray = false
                                continue
                            }
                            if isGrabbingArrayValues {
                                return (ValueStore(arrayData: arrayValues), "CODE_ARRAY")
                            }
                            errorInfo = (ErrorCode.arrayIndexNotFound, paths.count - 1)
                            return nil
                        }
                        
                        // exit occur after no matching key is found in object
                        if char == 125 && !isGrabbingNotation {
                            if tranversalHistory.count != 0 && !(copyObjectEntries && (processedPathIndex + 1) == paths.count) {
                                if tranversalHistory.count != 1 {
                                    tranversalHistory.removeLast()
                                    paths.insert(intermediateSymbol, at: processedPathIndex)
                                }
                                (processedPathIndex, advancedOffset) = tranversalHistory[tranversalHistory.count - 1]
                                isNavigatingUnknownPath = true
                                continue
                            }
                            if copyObjectEntries && (paths.count - 1) == processedPathIndex { return (ValueStore(entriesData: objectEntries), "CODE_ENTRIES") }
                            errorInfo = (ErrorCode.objectKeyNotFound, paths.count - 1)
                            return nil
                        }
                        
                        // copy json object/array data upon reading last path index
                        if processedPathIndex == paths.count {
                            if !copyObjectEntries { return (ValueStore(grabbedBytes), grabbingDataType) }
                            objectEntries.append((_asString(grabbingKey), JSONEntity(grabbedBytes, grabbingDataType)))
                            startSearchValue = false
                            isGrabbingNotation = false
                            processedPathIndex -= 1
                            advancedOffset -= 1
                        }
                    }
                    
                    if isGrabbingArrayValues {
                        // append after finishing copy single array/object element inside array during isGrabbingArrayValues mode
                        if isGrabbingNotation && notationBalance == (advancedOffset + 1) {
                            arrayValues.append(JSONEntity(grabbedBytes, grabbingDataType))
                            isGrabbingNotation = false
                        }
                    }
                    continue
                }
            }
            
            // ======== FINISHED HALDING JSON OPEN AND CLOSE NOTATION ==========
            if isGrabbingNotation {
                if !escapeCharacter && char == 34 {
                    isInQuotes = !isInQuotes
                }
                grabbedBytes.append(char)
            } else if startSearchValue {
                if notationBalance == advancedOffset || (isCountArray && (advancedOffset + 1) == notationBalance) {
                    // ====== HANDLING GRABBING STRINGS =========
                    // ignore escaped double quotation characters inside string values...
                    if !escapeCharacter && char == 34 {
                        isInQuotes = !isInQuotes
                        // array index matching does not apply on isGrabbingArrayValues as need to proccess all elements in the array
                        if isCountArray && !isGrabbingArrayValues && elementIndexCursor != pathArrayIndex {
                            if isInQuotes {
                                grabbingDataType = "string"
                            }
                            continue
                        }
                        // if not the last proccesed value skip caturing value
                        if !isGrabbingArrayValues &&
                         (processedPathIndex + (isCountArray ? 1 : 0)) != paths.count {
                            errorInfo = (ErrorCode.nonNestedParent, processedPathIndex - 1)
                            return nil
                        }
                        isGrabbingText = !isGrabbingText
                        if !isGrabbingText {
                            if !copyObjectEntries {
                                if isGrabbingArrayValues {
                                    arrayValues.append(JSONEntity(grabbedText, grabbingDataType))
                                    grabbedText = ""
                                    continue
                                }
                                return (ValueStore(grabbedText), "string")
                            }
                            // appending string elements to entries
                            // processedPathIndex is decrement to stop stimulation the overal stimulation is over
                            objectEntries.append((_asString(grabbingKey), JSONEntity(grabbedText, "string")))
                            startSearchValue = false
                            processedPathIndex -= 1
                            advancedOffset -= 1
                        } else {
                            grabbingDataType = "string"
                            grabbedText = ""
                        }
                        // used to copy values true, false, null and number
                    } else {
                        // ========== HANDLING GRABING NUMBERS, BOOLEANS AND NULL
                        
                        
                        if !isInQuotes && !isGrabbingText {
                            possibleType = ""
                            
                            if (char >= 48 && char <= 57) || char == 45 { possibleType = "number" }
                            else if char == 116 || char == 102 { possibleType = "boolean" }
                            else if char == 110 { possibleType = "null" }
                            if possibleType != "" {
                                grabbingDataType = possibleType
                                if isCountArray && !isGrabbingArrayValues && elementIndexCursor != pathArrayIndex { continue }
                                if !isGrabbingArrayValues && (processedPathIndex + (isCountArray ? 1 : 0)) != paths.count {
                                    errorInfo = (ErrorCode.nonNestedParent, processedPathIndex - 1)
                                    return nil
                                }
                                grabbedText = ""
                                grabbedText.append(Character(UnicodeScalar(char)))
                                isGrabbingText = true
                                continue
                            } else if char == 44 && isCountArray {
                                elementIndexCursor += 1
                            }
                            // handling comma notation in primitive values
                        } else if !isInQuotes && char == 44 {
                            if isCountArray {
                                elementIndexCursor += 1
                            }
                            if copyObjectEntries {
                                objectEntries.append((_asString(grabbingKey), JSONEntity(_trimSpace(grabbedText), grabbingDataType)))
                                startSearchValue = false
                                isGrabbingText = false
                                processedPathIndex -= 1
                                advancedOffset -= 1
                            } else  {
                                // the below block need to require to copy terminate primitive values and append on meeting ',' terminator...
                                if isGrabbingArrayValues {
                                    arrayValues.append(JSONEntity(_trimSpace(grabbedText), grabbingDataType))
                                    isGrabbingText = false
                                    grabbedText = ""
                                    continue
                                }
                                return (ValueStore(_trimSpace(grabbedText)), grabbingDataType)
                            }
                        } else if isGrabbingText {
                            grabbedText.append(Character(UnicodeScalar(char)))
                        }
                    }
                } else if char == 34 && !escapeCharacter {
                    isInQuotes = !isInQuotes
                }
                
                // ========= SECTION RESPONSIBLE HANDLING OBJECT KEY
            } else {
                if char == 34 && !escapeCharacter {
                    isInQuotes = !isInQuotes
                    // grabbing the matching correct object key as given in path
                    if (advancedOffset + 1) == notationBalance || isNavigatingUnknownPath {
                        isGrabbingKey = !isGrabbingKey
                        if isGrabbingKey {
                            grabbingKey = []
                        } else {
                            needProccessKey = true
                        }
                    }
                } else if isGrabbingKey {
                    grabbingKey.append(char)
                } else if needProccessKey && char == 58 {
                    needProccessKey = false
                    // if found start searching for object value for object key
                    if (copyObjectEntries && (processedPathIndex + 1) == paths.count) || grabbingKey == paths[processedPathIndex] {
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
    
    private func replaceEscapedQuotations(_ text: String) -> String {
        var replaced: String = ""
        var escaped: Bool = false
        for  char in text {
            if char == "\\" {
                escaped = true
            } else if escaped {
                if char == "\"" {
                    replaced.append("\"")
                } else {
                    replaced.append("\\")
                    replaced.append(char)
                }
                escaped = false
            } else {
                replaced.append(char)
            }
        }
        return replaced
    }
}
