public class JsonEntity {
    private var jsonText: String
    private var arrayValues:[String]? = nil
    
    public init(_ json:String) {
        jsonText = json
    }
    
    public func text(_ path:String? = nil) -> String? {
        return path == nil ? jsonText : decodeData(path!)
    }
    
    public func number(_ path:String? = nil) -> Float? {
        if path == nil { return Float(jsonText) }
        guard let value = decodeData(path!) else { return nil }
        return Float(value)
    }
    
    public func isNull(_ path:String? = nil) -> Bool? {
        if path == nil {
            return jsonText == "null"
        }
        guard let value = decodeData(path!) else { return nil }
        if value == "null" {
            return true
        }
        return false
    }
    
    public func object(_ path:String? = nil) -> JsonEntity? {
        if path == nil { return self }
        guard let value = decodeData(path!) else { return nil }
        return JsonEntity(value)
    }
    
    public func bool(_ path:String? = nil) -> Bool? {
        switch (path == nil ? jsonText : decodeData(path!)) {
            case "true": return true
            case "false": return false
            default: return nil
        }
    }
    
    public func array(_ path:String) -> [JsonEntity]? {
        arrayValues = []
        if decodeData("\(path).-1") != "$COMPLETE_ARRAY" { return nil }
        return arrayValues!.map({value in
            return JsonEntity(value)
        }) as [JsonEntity]
    }
    
    public func asJsonText() -> String {
        return jsonText
    }
    
    private func decodeData(_ inputPath:String) -> String? {
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
        
        var elementIndexCursor = -1
        var pathArrayIndex = -1
        var notationBalance = 0
        
        let copyArrayData:Bool = arrayValues != nil
        
        for char in jsonText {
            // if within quotation ignore processing json literals...
                        
            if !isInQuotes {
                if char == "{" || char == "[" {
                    notationBalance += 1
                    
                    if isCountArray {
                        if elementIndexCursor != pathArrayIndex {
                            if isGrabbingMultipleValues { grabbedText.append(char) }
                            continue
                        }
                        processedPathIndex += 1
                        isCountArray = false
                    }
                    if processedPathIndex == paths.count && !isGrabbingNotation {
                        grabbedText = ""
                        isGrabbingNotation = true
                    }
                    if isGrabbingNotation {
                        grabbedText.append(char)
                        continue
                    }
                    
                    if char == "[" && !isCountArray && (processedPathIndex + 1) == notationBalance {
                        let parsedIndex = Int(paths[processedPathIndex])
                        if parsedIndex == nil {
                            return nil
                        }
                        isCountArray = true
                        pathArrayIndex = parsedIndex!
                        elementIndexCursor = 0
                        startSearchValue = true
                        if copyArrayData && (processedPathIndex + 1) == paths.count {
                            isGrabbingMultipleValues = true
                        }
                    } else {
                        startSearchValue = false
                    }
                    
                    continue
                }
                
                if char == "}" || char == "]" {
                    notationBalance -= 1
                    
                    if isGrabbingText {
                        return grabbedText                    }
                    if isGrabbingNotation { grabbedText.append(char) }
                    if notationBalance == processedPathIndex {
                        if isCountArray {
                            if isGrabbingMultipleValues {
                                arrayValues!.append(grabbedText)
                                return "$COMPLETE_ARRAY"
                            }
                            return nil
                        }
                        if char == "}" && !startSearchValue { return nil }
                        if processedPathIndex == paths.count {
                            return grabbedText
                        }
                    }
                    if isGrabbingMultipleValues { grabbedText.append(char) }
                    continue
                }
                if isGrabbingNotation {
                    grabbedText.append(char)
                    continue
                }
            }
            
            if isGrabbingMultipleValues {
                if char == "," && (processedPathIndex + 1) == notationBalance {
                    arrayValues!.append(grabbedText)
                    grabbedText = ""
                } else {
                    grabbedText.append(char)
                }
                continue
            }
            
            if startSearchValue {
                if notationBalance == processedPathIndex || (isCountArray && (processedPathIndex + 1) == notationBalance) {
                    // if counting inside an array and check if arrived to correct item index
                    if  isCountArray && elementIndexCursor != pathArrayIndex {
                        if char == "," {
                            // if not matched then , character move to next element index
                            elementIndexCursor += 1
                        }
                        
                        if char == "\"" {
                            isInQuotes = !isInQuotes
                        }
                        continue
                    }
                    
                    if char == "\"" {
                        isInQuotes = !isInQuotes
                        isGrabbingText = !isGrabbingText
                        if !isGrabbingText {
                            return grabbedText
                        } else {
                            grabbedText = ""
                        }
                    } else if !isInQuotes && !isGrabbingText && (char.isNumber || char == "n" || char == "f" || char == "t") {
                        grabbedText.append(char)
                        isGrabbingText = true
                        continue
                    } else if isGrabbingText {
                        if !isInQuotes && char == "," {
                            return grabbedText
                        }
                        grabbedText.append(char)
                        continue
                    }
                }
            } else {
                // grabbing the matching correct object key as given in path
                if (processedPathIndex + 1) == notationBalance && char == "\"" {
                    isGrabbingKey = !isGrabbingKey
                    isInQuotes = !isInQuotes
                    if !isGrabbingKey {
                        // if found start searching for object value for object key
                        if grabbingKey == paths[processedPathIndex] {
                            processedPathIndex += 1
                            startSearchValue = true
                        }
                    } else {
                        grabbingKey = ""
                    }
                } else if isGrabbingKey {
                    grabbingKey.append(char)
                }
            }
        }
        return nil
    }
}
