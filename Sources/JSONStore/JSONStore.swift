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
    
    public enum ReplaceMode {
        case escapeQuotation
        case whitespace
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
