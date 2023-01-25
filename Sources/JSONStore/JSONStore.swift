import Foundation
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
            let content = ignoreType ? $0.replacingOccurrences(of: "\\\"", with: "\"") : $0
            return JSONEntity(content, "object")
        }, ignoreType: ignoreType)
    }
    
    public func bool(_ path: String? = nil, ignoreType: Bool = false) -> Bool? {
        return getField(path, "boolean", { $0 == "true" }, ignoreType: ignoreType)
    }
    
    public func array(_ path:String? = nil, ignoreType: Bool = false) -> [JSONEntity]? {
        if ignoreType {
            guard let arrayContent = getField(path, "string", { $0.replacingOccurrences(of: "\\\"", with: "\"") }, ignoreType: true) else { return nil }
            return JSONEntity(arrayContent).array()
        }
        copyArrayData = true
        let data = decodeData(path == nil ? "-1" : "\(path!).-1")
        if data?.value != "$COMPLETE_ARRAY" || data?.type != "code" {
            copyArrayData = false
            return nil
        }
        let results = arrayValues.map({value in
            return JSONEntity(value.value.trimmingCharacters(in: .whitespacesAndNewlines), value.type)
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
            return (value.key, JSONEntity(value.value.trimmingCharacters(in: .whitespacesAndNewlines), value.type))
        }) as [(String, JSONEntity)]
        copyObjectEntries = false
        return results
    }

    private func resolveValue(value: String, type: String, serialization: SerializationType? = nil) -> Any {
        switch(type) {
            case "number": return Double(value)!
        case "object":
            if serialization == .none {
                return JSONEntity(value, "object")
            }
            if serialization == .singular {
                return value
            }
            
            var objData: [String: Any] = [String: Any]()
            JSONEntity(value, type).entries("")!.forEach({
                key, nestedValue in objData[key] = resolveValue(value: nestedValue.jsonText, type: nestedValue.contentType, serialization: serialization)
            })
            return objData
            
        case "array":
            if serialization == .none {
                return JSONEntity(value, "array").array()!
            }
            if serialization == .singular {
                return value
            }
            return JSONEntity(value).array()!
                .map({ item in
                    return resolveValue(value: item.jsonText, type: item.contentType, serialization: serialization)
                }) as [Any]
            
            case "boolean": return value == "true" ? true : false
            case "null": return NSNull()
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
    
    public func serialize(_ serializeMode: SerializationType) -> Any {
        return resolveValue(value: jsonText, type: contentType, serialization: serializeMode)
    }
    
    public func serialize(_ path: String, _ serializeMode: SerializationType) -> Any? {
        guard let (value, type) = decodeData(path) else { return nil }
        return resolveValue(value: value, type: type, serialization: serializeMode)
    }
    
    public func capture(_ path: String) -> JSONEntity? {
        guard let result = decodeData(path) else { return nil }
        return JSONEntity(result.value, result.type)
    }
    
    private func decodeData(_ inputPath:String) -> (value: String, type: String)? {
        var result = breakdown(inputPath, arrayValues: &arrayValues, objectEntries: &objectEntries, copyArrayData: copyArrayData, copyObjectEntries: copyObjectEntries, jsonText: jsonText)
        if result != nil {
            result!.value = result!.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
