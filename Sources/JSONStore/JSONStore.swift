public enum Constants {
    /// .NULL used to represent null JSON values on export() and value()
    case NULL
}

public class JSONEntity {
    private static let INVALID_START_CHARACTER_ERROR = "[JSONStore] the first character of given json content is neither starts with '{' or '['. Make sure the given content is valid JSON"
    private static let INVALID_BUFFER_INITIALIZATION = "[JSONStore] instance has not properly initialized. Problem had occured when assigning input data buffer which occur when the provider callback given on .init(provider:) gives nil or when exception thrown within provider callback itself. Check the result given by by provider callback to resolve the issue."
    
    private var jsonText: String = ""
    private var jsonData: UnsafeRawBufferPointer = UnsafeRawBufferPointer.init(start: nil, count: 0)
    private var arrayValues:[JSONEntity] = []
    private var objectEntries:[(key: String, value: JSONEntity)] = []
    private var contentType:String
    private var copyArrayData:Bool = false
    private var copyObjectEntries:Bool = false
    private var intermediateSymbol: String.SubSequence = "???"
    private var pathSpliter: Character = "."
    private var typeMismatchWarningCount = 0
    
    public enum JSONType: String {
        case string = "string"
        case boolean = "boolean"
        case object = "object"
        case array = "array"
        case number = "number"
        case null = "null"
        case unclassified = "notInit"
        
        init(_ v: String) {
            self = .init(rawValue: v)!
        }
    }
        
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
    
    public init(_ provider:  ((UnsafeRawBufferPointer?) throws -> UnsafeRawBufferPointer?) throws -> UnsafeRawBufferPointer?) {
        guard let buffer = try? provider({$0}) else {
            print(JSONEntity.INVALID_BUFFER_INITIALIZATION)
            contentType = "notInit"
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

    public init(_ provider:  ((UnsafeRawBufferPointer?)  -> UnsafeRawBufferPointer?) -> UnsafeRawBufferPointer?) {
        guard let buffer = provider({$0}) else {
            print(JSONEntity.INVALID_BUFFER_INITIALIZATION)
            contentType = "notInit"
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

    
    private init(_ json: String, _ type: String) {
        jsonText = json
        contentType = type
        if contentType == "object" {
            jsonData = UnsafeRawBufferPointer(start: jsonText.withUTF8({$0}).baseAddress, count: jsonText.count)
        }
    }
    
    /// set token to represent intermediate paths.
    /// 
    /// Intermediate token capture one or more dynamic intermediate paths. Default token is ???
    public func setIntermediateRepresentor (_ representer: String) -> JSONEntity {
        intermediateSymbol = String.SubSequence(representer)
        return self
    }

    /// set character to path segmenent given in string. Default is (.) dot notation.
    /// You can use this in case if key attribute also have dot notation.
    /// It is best if the split character is a speacial character
    public func setSpliter(_ splitRepresenter: Character) -> JSONEntity {
        pathSpliter = splitRepresenter
        return self
    }
    
    private func getField <T>(_ path: String?, _ fieldName: String, _ mapper: (String) -> T?, ignoreType:Bool = false) -> T? {
        guard let (data, type) = path == nil ? (jsonText, contentType) : decodeData(path!) else { return nil; }
        if !ignoreType && type != fieldName {
            if typeMismatchWarningCount != 3 {
                print("[JSONStore] type constrained query expected \(fieldName) but \(type) type value was read instead therefore returned nil. This warning will not be shown after 3 times per instance")
                typeMismatchWarningCount += 1
            }
            return nil
        }
        return mapper(data)
    }
    
    /// Get string value of the given addressed path.
    public func string(_ path:String? = nil) -> String? {
        return getField(path, "string", { $0 })
    }
    
    /// Get number value of the given addressed path.
    public func number(_ path:String? = nil, ignoreType: Bool = false) -> Double? {
        return getField(path, "number", { Double($0) }, ignoreType: ignoreType)
    }
    
    /// Check if the element of the given addressed path represent a null value.
    public func isNull(_ path:String? = nil) -> Bool? {
        guard let type = path == nil ? contentType: decodeData(path!)?.type else {
            return nil
        }
        return type == "null"
    }
    
    /// Get object value as a node of the given addressed path. Activate ignoreType to parse addressed string to json object.
    public func object(_ path:String? = nil, ignoreType: Bool = false) -> JSONEntity? {
        if path == nil { return self }
        return getField(path, "object", {
            JSONEntity(ignoreType ? replaceEscapedQuotations($0) : $0, "object")
        }, ignoreType: ignoreType)
    }
    
    /// Get boolean value of the given addressed path
    public func bool(_ path: String? = nil, ignoreType: Bool = false) -> Bool? {
        return getField(path, "boolean", { $0 == "true" }, ignoreType: ignoreType)
    }
    
    /// Get collection of nodes addressed by the given path. Activate ignoreType to parse addressed string to json array .
    public func array(_ path:String? = nil, ignoreType: Bool = false) -> [JSONEntity]? {
        if ignoreType {
            guard let arrayContent = getField(path, "string", { replaceEscapedQuotations($0) }, ignoreType: true) else { return nil }
            return JSONEntity(arrayContent).array()
        }
        copyArrayData = true
        let data = decodeData(path == nil ? "-1" : "\(path!).-1")
        if data?.value != "$COMPLETE_ARRAY" || data?.type != "code" {
            copyArrayData = false
            return nil
        }
        copyArrayData = false
        return arrayValues
    }
    
    /// Check if attribute or element exists on given address path
    public func isExist(_ path:String) -> Bool {
        return decodeData(path) != nil
    }
    
    /// Get collection if key-value pair of the pointed object. The path must point to object type
    public func entries(_ path: String? = nil) -> [(key: String, value: JSONEntity)]? {
        copyObjectEntries = true
        let data = decodeData(path == nil || path!.count == 0 ? "dummyAtr" : "\(path!).dummyAtr")
        if data?.value != "$COMPLETE_OBJECT" || data?.type != "code" {
            copyObjectEntries = false
            return nil
        }
        copyObjectEntries = false
        return objectEntries
    }

    private func resolveValue(value: String, type: String, serialize: Bool = false) -> Any {
        switch(type) {
            case "number": return Double(value)!
        case "object":
            if !serialize {
                return JSONEntity(value, "object")
            }
            
            var objData: [String: Any] = [String: Any]()
            JSONEntity(value, type).entries("")!.forEach({
                key, nestedValue in objData[key] = resolveValue(value: nestedValue.jsonText, type: nestedValue.contentType, serialize: serialize)
            })
            return objData
            
        case "array":
            if !serialize {
                return JSONEntity(value, "array").array()!
            }
         
            return JSONEntity(value).array()!
                .map({ item in
                    return resolveValue(value: item.jsonText, type: item.contentType, serialize: serialize)
                }) as [Any]
            
            case "boolean": return value == "true" ? true : false
        case "null": return Constants.NULL
            default: return value
        }
    }
    
    /// Read a json element without type constraints.
    /// Similar to calling string(), array(), object() .etc but without knowing the type queried value
    /// - Returns: the value addressed by the path and its type is returned as a tuple
    public func value(_ path: String? = nil) -> (value: Any, type: JSONType)? {
        guard let (value, type) = (path == nil ? (jsonText, contentType) : decodeData(path!)) else { return nil }
        return (resolveValue(value: value, type: type), JSONType(type))
    }
    
    /// get the type of value held by the content of this node
    public func type() -> JSONType {
        return JSONType(contentType)
    }
    
    /// dump the contents of this node as a string
    public func dump(_ path: String? = nil) -> String? {
        return path == nil ? jsonText : decodeData(path!)?.value
    }
    
    /// Get the natural value of JSON element expressed associated swift type (except null represented in JSONStore.Constants.NULL).
    /// If array then collection is returned where subelement also recursively procesed till to their primitive values.
    /// If object then collection of key-value tupple is given. Like arrays value is also recursivelty proccessed
    public func export() -> Any {
        return resolveValue(value: jsonText, type: contentType, serialize: true)
    }
    
    /// Read a json element without type constraints.
    /// Similar to calling string(), array(), object() .etc but without knowing the type queried value
    /// - Returns: the value addressed by the path and its type is returned as a tuple
    public func export(_ path: String) -> Any? {
        guard let (value, type) = decodeData(path) else { return nil }
        return resolveValue(value: value, type: type, serialize: true)
    }
    
    /// capture the node addresss by the given path.
    public func capture(_ path: String) -> JSONEntity? {
        guard let result = decodeData(path) else { return nil }
        return JSONEntity(result.value, result.type)
    }
    
    private func decodeData(_ inputPath:String) -> (value: String, type: String)? {
        return decodeBytes(inputPath, arrayValues: &arrayValues, objectEntries: &objectEntries, copyArrayData: copyArrayData, copyObjectEntries: copyObjectEntries)
    }
    
    private func trimSpace(_ input: String) -> String {
        var output = input
        while(output.last!.isWhitespace) {
            output.removeLast()
        }
        return output
    }

    func decodeBytes(_ inputPath:String, arrayValues: inout [JSONEntity], objectEntries: inout [(key: String, value: JSONEntity)], copyArrayData: Bool, copyObjectEntries: Bool) -> (value: String, type: String)? {
        if !(contentType == "object" || contentType == "array") {
            return nil
        }
        var paths = inputPath.split(separator: pathSpliter)
        var processedPathIndex = 0
        var isNavigatingUnknownPath = false
        var additionalTransversals = 0
        var tranversalHistory: [(processedPathIndex: Int, additionalTransversals: Int)] = []

        var isInQuotes = false
        var startSearchValue = false
        var isGrabbingText = false
        var grabbedText = ""
        var grabbingKey = ""
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
        
        arrayValues = []
        objectEntries = []
        
        if paths.last == intermediateSymbol {
            print("[JSONStore] the path cannot be end with a intermediate representer - \(intermediateSymbol)")
            return nil
        }
        
        for char in jsonData {
            // if within quotation ignore processing json literals...
            if !isInQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                    if isCountArray && !isGrabbingArrayValues {
                        // ignore processing if element in not matching the array index except when grabbing all elements on array
                        if elementIndexCursor != pathArrayIndex {

                            // start grabbing array/object array elements on isGrabbingArrayValues mode
                            if isGrabbingArrayValues {
                                if notationBalance == processedPathIndex + additionalTransversals + 2 {
                                    grabbingDataType = char == 123 ? "object" : "array"
                                }
                                grabbedText.append(Character(UnicodeScalar(char)))
                            }
                            continue
                        }
                        // if element found for matched index stop array searching ..
                        processedPathIndex += 1
                        isCountArray = false
                    }
                    // if the last value of last key is object or array then start copy it
                    if (processedPathIndex == paths.count || isGrabbingArrayValues) && !isGrabbingNotation {
                        grabbedText = ""
                        isGrabbingNotation = true
                        grabbingDataType = char == 123 ? "object" : "array"
                    }
                    
                    // continue copying object/arrray inner characters...
                    if isGrabbingNotation {
                        grabbedText.append(Character(UnicodeScalar(char)))
                        continue
                    }
                    
                    // intiate elements counting inside array on reaching open bracket...
                    if char == 91 && !isCountArray && ((processedPathIndex + additionalTransversals + 1) == notationBalance || isNavigatingUnknownPath) {
                        let parsedIndex = Int(paths[processedPathIndex])
                        // occur when trying to access element of array with non-number index
                        if parsedIndex == nil {
                           if paths[processedPathIndex] == intermediateSymbol {
                                paths.remove(at: processedPathIndex)
                                isNavigatingUnknownPath = true
                                tranversalHistory.append((processedPathIndex, additionalTransversals))
                                continue
                           } else if isNavigatingUnknownPath { continue }
                            return nil
                        }
                        if isNavigatingUnknownPath {
                            isNavigatingUnknownPath = false
                            additionalTransversals = notationBalance - processedPathIndex - 1
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
                            tranversalHistory.append((processedPathIndex, additionalTransversals))
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
                            objectEntries.append((grabbingKey, JSONEntity(grabbedText, grabbingDataType)))
                            return ("$COMPLETE_OBJECT", "code")
                        } else if isGrabbingArrayValues {
                            // append the pending grabbing text
                            arrayValues.append(JSONEntity(trimSpace(grabbedText), grabbingDataType))
                        } else {
                            return (trimSpace(grabbedText), grabbingDataType)
                        }
                    }
                    if isGrabbingNotation { grabbedText.append(Character(UnicodeScalar(char))) }
                    
                    // occur after all element in foccused array or object is finished searching...
                    if notationBalance == processedPathIndex + additionalTransversals {
                        if isCountArray && char == 93 {
                            // occur when when not matching element is found for given array index and array finished iterating...
                            if tranversalHistory.count != 0 {
                                if tranversalHistory.count != 1 {
                                    tranversalHistory.removeLast()
                                    paths.insert(intermediateSymbol, at: processedPathIndex)
                                }
                                (processedPathIndex, additionalTransversals) = tranversalHistory[tranversalHistory.count - 1]
                                isNavigatingUnknownPath = true
                                isCountArray = false
                                continue
                            }
                            if isGrabbingArrayValues {
                                return ("$COMPLETE_ARRAY", "code")
                            }
                            return nil
                        }
                        
                        // exit occur after no matching key is found in object
                        if char == 125 && !isGrabbingNotation {
                            if tranversalHistory.count != 0 {
                                if tranversalHistory.count != 1 {
                                    tranversalHistory.removeLast()
                                    paths.insert(intermediateSymbol, at: processedPathIndex)
                                }
                                (processedPathIndex, additionalTransversals) = tranversalHistory[tranversalHistory.count - 1]
                                isNavigatingUnknownPath = true
                                continue
                            }
                            if copyObjectEntries { return ("$COMPLETE_OBJECT", "code") }
                            return nil
                        }
                        
                        // copy json object/array data upon reading last path index
                        if processedPathIndex == paths.count {
                            if !copyObjectEntries { return (grabbedText, grabbingDataType) }
                            objectEntries.append((grabbingKey, JSONEntity(grabbedText, grabbingDataType)))
                            startSearchValue = false
                            isGrabbingNotation = false
                            processedPathIndex -= 1
                        }
                    }
                    
                    if isGrabbingArrayValues {
                        // append after finishing copy single array/object element inside array during isGrabbingArrayValues mode
                        if isGrabbingNotation && notationBalance == (processedPathIndex + additionalTransversals + 1) {
                            arrayValues.append(JSONEntity(grabbedText, grabbingDataType))
                            isGrabbingNotation = false
                        }
                    }
                    continue
                }
            }
            
            if isGrabbingNotation {
                if !escapeCharacter && char == 34 {
                    isInQuotes = !isInQuotes
                }
                grabbedText.append(Character(UnicodeScalar(char)))
            } else if startSearchValue {
                if notationBalance == processedPathIndex + additionalTransversals || (isCountArray && (processedPathIndex + additionalTransversals + 1) == notationBalance) {
                    // ignore escaped double quotation characters inside string values...
                    if !escapeCharacter && char == 34 {
                        isInQuotes = !isInQuotes
                        // if not the last proccesed value skip caturing value
                        if !isGrabbingArrayValues && 
                         (processedPathIndex + (isCountArray ? 1 : 0)) != paths.count {
                            continue
                        }
                        // array index matching does not apply on isGrabbingArrayValues as need to proccess all elements in the array
                        if isCountArray && !isGrabbingArrayValues && elementIndexCursor != pathArrayIndex {
                            if isInQuotes {
                                grabbingDataType = "string"
                            }
                            continue
                        }
                        isGrabbingText = !isGrabbingText
                        if !isGrabbingText {
                            if !copyObjectEntries {
                                if isGrabbingArrayValues {
                                    arrayValues.append(JSONEntity(grabbedText, grabbingDataType))
                                    grabbedText = ""
                                    continue
                                }
                                return (grabbedText, "string")
                            }
                            // appending string elements to entries
                            // processedPathIndex is decrement to stop stimulation the overal stimulation is over
                            objectEntries.append((grabbingKey, JSONEntity(grabbedText, "string")))
                            startSearchValue = false
                            processedPathIndex -= 1
                        } else {
                            grabbingDataType = "string"
                            grabbedText = ""
                        }
                        // used to copy values true, false, null and number
                    } else {
                        // handling numbers, booleans and null...
                        
                        possibleType = ""
                        
                        if (char >= 48 && char <= 57) || char == 45 { possibleType = "number" }
                        else if char == 116 || char == 102 { possibleType = "boolean" }
                        else if char == 110 { possibleType = "null" }
                        
                        if !isInQuotes && !isGrabbingText && possibleType != "" {
                            if !isGrabbingArrayValues && (processedPathIndex + (isCountArray ? 1 : 0)) != paths.count {
                                continue
                            }
                            grabbingDataType = possibleType
                            if isCountArray && !isGrabbingArrayValues && elementIndexCursor != pathArrayIndex { continue }
                            grabbedText = ""
                            grabbedText.append(Character(UnicodeScalar(char)))
                            isGrabbingText = true
                            continue
                        } else if !isInQuotes && char == 44 {
                            if isCountArray {
                                elementIndexCursor += 1
                            }
                            if isGrabbingText {
                                if copyObjectEntries {
                                    objectEntries.append((grabbingKey, JSONEntity(grabbedText, grabbingDataType)))
                                    startSearchValue = false
                                    isGrabbingText = false
                                    processedPathIndex -= 1
                                } else  {
                                    // the below block need to require to copy terminate primitive values and append on meeting ',' terminator...
                                    if isGrabbingArrayValues {
                                        arrayValues.append(JSONEntity(grabbedText, grabbingDataType))
                                        isGrabbingText = false
                                        grabbedText = ""
                                        continue
                                    }
                                    return (trimSpace(grabbedText), grabbingDataType)
                                }
                            } else if !isCountArray {
                                startSearchValue = false
                            }
                        } else if isGrabbingText {
                            grabbedText.append(Character(UnicodeScalar(char)))
                        }
                    }
                } else if char == 34 && !escapeCharacter {
                    isInQuotes = !isInQuotes
                    if !isInQuotes {
                        startSearchValue = false
                    }
                } else if !isInQuotes && char == 44 && !isCountArray {
                    startSearchValue = false
                }
                
                // section responsible for finding matching key in object notation
            } else {
                if char == 34 && !escapeCharacter {
                    isInQuotes = !isInQuotes
                    // grabbing the matching correct object key as given in path
                    if (processedPathIndex + 1 + additionalTransversals) == notationBalance || isNavigatingUnknownPath {
                        isGrabbingKey = !isGrabbingKey
                        if !isGrabbingKey {
                            startSearchValue = true
                            // if found start searching for object value for object key
                            if (copyObjectEntries && (processedPathIndex + 1) == paths.count) || grabbingKey == paths[processedPathIndex] {
                                processedPathIndex += 1
                                if isNavigatingUnknownPath {
                                    isNavigatingUnknownPath = false
                                    additionalTransversals = notationBalance - processedPathIndex
                                }
                            }
                        } else {
                            grabbingKey = ""
                        }
                    }
                } else if isGrabbingKey {
                    grabbingKey.append(Character(UnicodeScalar(char)))
                }
            }
            
            if escapeCharacter {
                escapeCharacter = false
            } else if char == 92 {
                escapeCharacter = true
            }
        }
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
