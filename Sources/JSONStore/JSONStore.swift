public enum Constants {
    case NULL
}

public class JSONEntity {
    private var jsonText: String
    private var arrayValues:[(value: String, type: String)] = []
    private var objectEntries:[(key: String, value: String, type: String)] = []
    private var contentType:String
    private var copyArrayData:Bool = false
    private var copyObjectEntries:Bool = false
    
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
    
    public enum SerializationType {
        case singular
        case container
    }
        
    public init(_ json:String) {
        jsonText = json
        switch (jsonText.first) {
            case "{": contentType = "object"
            case "[": contentType = "array"
            default: contentType = "string"
        }
    }
    
    private init(_ json: String, _ type: String) {
        jsonText = json
        contentType = type
    }
    
    private func getField <T>(_ path: String?, _ fieldName: String, _ mapper: (String) -> T?, ignoreType:Bool = false) -> T? {
        guard let (data, type) = path == nil ? (jsonText, contentType) : decodeData(path!) else { return nil; }
        if !ignoreType && type != fieldName { return nil }
        return mapper(data)
    }
    
    public func string(_ path:String? = nil) -> String? {
        return getField(path, "string", { $0 })
    }
    
    public func number(_ path:String? = nil, ignoreType: Bool = false) -> Double? {
        return getField(path, "number", { Double($0) }, ignoreType: ignoreType)
    }
    
    public func isNull(_ path:String? = nil) -> Bool? {
        guard let type = path == nil ? contentType: decodeData(path!)?.type else {
            return nil
        }
        return type == "null"
    }
    
    public func object(_ path:String? = nil, ignoreType: Bool = false) -> JSONEntity? {
        if path == nil { return self }
        return getField(path, "object", {
            let content = ignoreType ? replaceEscapedQuotations($0) : $0
            return JSONEntity(content, "object")
        }, ignoreType: ignoreType)
    }
    
    public func bool(_ path: String? = nil, ignoreType: Bool = false) -> Bool? {
        return getField(path, "boolean", { $0 == "true" }, ignoreType: ignoreType)
    }
    
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
        let results = arrayValues.map({value in
            return JSONEntity(trimWhiteSpace(value.value, value.type), value.type)
        }) as [JSONEntity]
        copyArrayData = false
        return results
    }
    
    public func isExist(_ path:String) -> Bool {
        return decodeData(path) != nil
    }
    
    public func entries(_ path: String? = nil) -> [(key: String, value: JSONEntity)]? {
        copyObjectEntries = true
        let data = decodeData(path == nil || path!.count == 0 ? "dummyAtr" : "\(path!).dummyAtr")
        if data?.value != "$COMPLETE_OBJECT" || data?.type != "code" {
            copyObjectEntries = false
            return nil
        }
        let results = objectEntries.map({ value in
            return (value.key, JSONEntity(trimWhiteSpace(value.value, value.type), value.type))
        }) as [(String, JSONEntity)]
        copyObjectEntries = false
        return results
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
    
    
    public func value(_ path: String? = nil) -> (value: Any, type: JSONType)? {
        guard let (value, type) = (path == nil ? (jsonText, contentType) : decodeData(path!)) else { return nil }
        return (resolveValue(value: value, type: type), JSONType(type))
    }
    
    public func type() -> JSONType {
        return JSONType(contentType)
    }
    
    public func dump(_ path: String? = nil) -> String? {
        return path == nil ? jsonText : decodeData(path!)?.value
    }
    
    public func export() -> Any {
        return resolveValue(value: jsonText, type: contentType, serialize: true)
    }
    
    public func export(_ path: String) -> Any? {
        guard let (value, type) = decodeData(path) else { return nil }
        return resolveValue(value: value, type: type, serialize: true)
    }
    
    public func capture(_ path: String) -> JSONEntity? {
        guard let result = decodeData(path) else { return nil }
        return JSONEntity(result.value, result.type)
    }
    
    private func decodeData(_ inputPath:String) -> (value: String, type: String)? {
        var result = breakdown(inputPath, arrayValues: &arrayValues, objectEntries: &objectEntries, copyArrayData: copyArrayData, copyObjectEntries: copyObjectEntries, jsonText: jsonText)
        if result != nil {
            result!.value = trimWhiteSpace(result!.value, result!.type)
        }
        return result
    }
            
    func breakdown(_ inputPath:String, arrayValues: inout [(value: String, type: String)], objectEntries: inout [(key: String, value: String, type: String)], copyArrayData: Bool, copyObjectEntries: Bool, jsonText: String  ) -> (value: String, type: String)? {
        let paths = inputPath.split(separator: ".")
        var processedPathIndex = 0

        var isInQuotes = false
        var startSearchValue = false
        var isGrabbingText = false
        var grabbedText = ""
        var grabbingKey = ""
        var isGrabbingNotation = false
        var isGrabbingKey = false
        var isCountArray = false
        var isGrabbingMultipleValues = false
        
        var elementIndexCursor = -1 // the count variable when iterating array
        var pathArrayIndex = -1 // the array index of given on path
        var notationBalance = 0
        var grabbingDataType: String = "string"
        var possibleType: String = ""
        var escapeCharacter: Bool = false
        
        arrayValues = []
        objectEntries = []
        
        for char in jsonText {
            // if within quotation ignore processing json literals...
            if !isInQuotes {
                if char == "{" || char == "[" {
                    notationBalance += 1
                    if isCountArray && !isGrabbingMultipleValues {
                        // ignore processing if element in not matching the array index except when grabbing all elements on array
                        if elementIndexCursor != pathArrayIndex {

                            // start grabbing array/object array elements on isGrabbingMultipleValues mode
                            if isGrabbingMultipleValues {
                                if notationBalance == processedPathIndex + 2 {
                                    grabbingDataType = char == "{" ? "object" : "array"
                                }
                                grabbedText.append(char)
                            }
                            continue
                        }
                        // if element found for matched index stop array searching ..
                        processedPathIndex += 1
                        isCountArray = false
                    }
                    // if the last value of last key is object or array then start copy it
                    if (processedPathIndex == paths.count || isGrabbingMultipleValues) && !isGrabbingNotation {
                        grabbedText = ""
                        isGrabbingNotation = true
                        grabbingDataType = char == "{" ? "object" : "array"
                    }
                    
                    // continue copying object/arrray inner characters...
                    if isGrabbingNotation {
                        grabbedText.append(char)
                        continue
                    }
                    
                    // intiate elements counting inside array on reaching open bracket...
                    if char == "[" && !isCountArray && (processedPathIndex + 1) == notationBalance {
                        let parsedIndex = Int(paths[processedPathIndex])
                        // occur when trying to access element of array with non-number index
                        if parsedIndex == nil {
                            return nil
                        }
                        isCountArray = true
                        pathArrayIndex = parsedIndex!
                        elementIndexCursor = 0
                        startSearchValue = true
                        
                        // start to copy all element of array given on last path index
                        if copyArrayData && (processedPathIndex + 1) == paths.count {
                            isGrabbingMultipleValues = true
                        }
                    } else {
                        // move to next nest object and start looking attribute key on next nested object...
                        startSearchValue = false
                    }
                    continue
                }
                
                if char == "}" || char == "]" {
                    notationBalance -= 1
                    
                    // if a primitive value is in proccess copying then return copied value
                    if isGrabbingText {
                        // when finished copy last primitive value on copyObjectEntries mode. Need to make sure the parent container notation is an object
                        if copyObjectEntries && char == "}" {
                            objectEntries.append((grabbingKey, grabbedText, grabbingDataType))
                            return ("$COMPLETE_OBJECT", "code")
                        } else if isGrabbingMultipleValues {
                            // append the pending grabbing text
                            arrayValues.append((grabbedText, grabbingDataType))
                        } else {
                            return (grabbedText, grabbingDataType)
                        }
                    }
                    if isGrabbingNotation { grabbedText.append(char) }
                    
                    // occur after all element in foccused array or object is finished searching...
                    if notationBalance == processedPathIndex {
                        if isCountArray && char == "]" {
                            // occur when when not matching element is found for given array index and array finished iterating...
                            if isGrabbingMultipleValues {
                                return ("$COMPLETE_ARRAY", "code")
                            }
                            return nil
                        }
                        
                        // exit occur after no matching key is found in object
                        if char == "}" && !startSearchValue {
                            if copyObjectEntries { return ("$COMPLETE_OBJECT", "code") }
                            return nil
                        }
                        
                        // copy json object/array data upon reading last path index
                        if processedPathIndex == paths.count {
                            if !copyObjectEntries { return (grabbedText, grabbingDataType) }
                            objectEntries.append((grabbingKey, grabbedText , grabbingDataType))
                            startSearchValue = false
                            isGrabbingNotation = false
                            processedPathIndex -= 1
                        }
                    }
                    
                    if isGrabbingMultipleValues {
                        // append after finishing copy single array/object element inside array during isGrabbingMultipleValues mode
                        if isGrabbingNotation && notationBalance == (processedPathIndex + 1) {
                            arrayValues.append((grabbedText, grabbingDataType))
                            isGrabbingNotation = false
                        }
                    }
                    continue
                }
            }
            
            if isGrabbingNotation {
                if !escapeCharacter && char == "\"" {
                    isInQuotes = !isInQuotes
                }
                grabbedText.append(char)
            } else if startSearchValue {
                if notationBalance == processedPathIndex || (isCountArray && (processedPathIndex + 1) == notationBalance) {
                    // ignore escaped double quotation characters inside string values...
                    if !escapeCharacter && char == "\"" {
                        isInQuotes = !isInQuotes
                        // array index matching does not apply on isGrabbingMultipleValues as need to proccess all elements in the array
                        if isCountArray && !isGrabbingMultipleValues && elementIndexCursor != pathArrayIndex {
                            if isInQuotes {
                                grabbingDataType = "string"
                            }
                            continue
                        }
                        isGrabbingText = !isGrabbingText
                        if !isGrabbingText {
                            if !copyObjectEntries {
                                if isGrabbingMultipleValues {
                                    arrayValues.append((grabbedText, grabbingDataType))
                                    grabbedText = ""
                                    continue
                                }
                                return (grabbedText, "string")
                            }
                            // appending string elements to entries
                            // processedPathIndex is decrement to stop stimulation the overal stimulation is over
                            objectEntries.append((grabbingKey, grabbedText, "string"))
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
                        
                        if char.isNumber || char == "-" { possibleType = "number" }
                        else if char == "t" || char == "f" { possibleType = "boolean" }
                        else if char == "n" { possibleType = "null" }
                        
                        if !isInQuotes && !isGrabbingText && possibleType != "" {
                            grabbingDataType = possibleType
                            if isCountArray && !isGrabbingMultipleValues && elementIndexCursor != pathArrayIndex { continue }
                            grabbedText = ""
                            grabbedText.append(char)
                            isGrabbingText = true
                            continue
                        } else if !isInQuotes && char == "," {
                            if isCountArray {
                                elementIndexCursor += 1
                            }
                            if isGrabbingText {
                                if copyObjectEntries {
                                    objectEntries.append((grabbingKey, grabbedText, grabbingDataType))
                                    startSearchValue = false
                                    isGrabbingText = false
                                    processedPathIndex -= 1
                                } else  {
                                    // the below block need to require to copy terminate primitive values and append on meeting ',' terminator...
                                    if isGrabbingMultipleValues {
                                        arrayValues.append((grabbedText, grabbingDataType))
                                        isGrabbingText = false
                                        grabbedText = ""
                                        continue
                                    }
                                    return (grabbedText, grabbingDataType)
                                }
                            }
                        } else if isGrabbingText {
                            grabbedText.append(char)
                        }
                    }
                } else if char == "\"" && !escapeCharacter {
                    isInQuotes = !isInQuotes
                }
                
                // section responsible for finding matching key in object notation
            } else {
                if char == "\"" && !escapeCharacter {
                    isInQuotes = !isInQuotes
                    // grabbing the matching correct object key as given in path
                    if (processedPathIndex + 1) == notationBalance {
                        isGrabbingKey = !isGrabbingKey
                        if !isGrabbingKey {
                            // if found start searching for object value for object key
                            if (copyObjectEntries && (processedPathIndex + 1) == paths.count) || grabbingKey == paths[processedPathIndex] {
                                processedPathIndex += 1
                                startSearchValue = true
                            }
                        } else {
                            grabbingKey = ""
                        }
                    }
                } else if isGrabbingKey {
                    grabbingKey.append(char)
                }
            }
            
            if escapeCharacter {
                escapeCharacter = false
            } else if char == "\\" {
                escapeCharacter = true
            }
        }
        return nil
    }
    
    private func trimWhiteSpace(_ text: String, _ type: String) -> String{
        if type == "string" || type == "object" || type == "array" {
            return text
        }
        var replaced: String = ""
        for char in text {
            if !char.isWhitespace {
                replaced.append(char)
            }
        }
        return replaced
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
