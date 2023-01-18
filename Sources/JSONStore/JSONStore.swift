public class JsonEntity {
    private var jsonText: String
    private var arrayValues:[String]? = nil
    private var objectEntries:[(key:String, value:String)]? = nil
    
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
    
    public func array(_ path:String? = nil) -> [JsonEntity]? {
        arrayValues = []
        if decodeData(path == nil ? "-1" : "\(path!).-1") != "$COMPLETE_ARRAY" {
            arrayValues = nil
            return nil
        }
        let results = arrayValues!.map({value in
            return JsonEntity(value)
        }) as [JsonEntity]
        arrayValues = nil
        return results
    }
    
    public func isExist(_ path:String) -> Bool {
        return decodeData(path) != nil
    }
    
    public func entries(_ path:String) -> [(key: String, value: JsonEntity)]? {
        objectEntries = []
        if decodeData("\(path).dummyAtr") != "$COMPLETE_OBJECT" {
            objectEntries = nil
            return nil
        }
        let results = objectEntries!.map({ value in
            return (value.key, JsonEntity(value.value))
        }) as [(String, JsonEntity)]
        objectEntries = nil
        return results
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
        
        var elementIndexCursor = -1 // the count variable when iterating array
        var pathArrayIndex = -1 // the array index of given on path
        var notationBalance = 0
        
        let copyArrayData:Bool = arrayValues != nil
        let copyObjectEntries:Bool = objectEntries != nil
        
        for char in jsonText {
            // if within quotation ignore processing json literals...
            if !isInQuotes {
                if char == "{" || char == "[" {
                    notationBalance += 1
                    
                    if isCountArray {
                        // ignore processing if element in not matching the array index
                        if elementIndexCursor != pathArrayIndex {
                            if isGrabbingMultipleValues { grabbedText.append(char) }
                            continue
                        }
                        processedPathIndex += 1
                        isCountArray = false
                    }
                    // if the last value of last key is object or array then start copy it
                    if processedPathIndex == paths.count && !isGrabbingNotation {
                        grabbedText = ""
                        isGrabbingNotation = true
                    }
                    // continue copying object/arrray notation...
                    if isGrabbingNotation {
                        grabbedText.append(char)
                        continue
                    }
                    
                    // starting to count elements in array on reaching open bracket...
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
                        // start to copy all element in array on last -1 index
                        if copyArrayData && (processedPathIndex + 1) == paths.count {
                            isGrabbingMultipleValues = true
                        }
                    } else {
                        // upon meeting open 'notation' searching for next key on next path should start
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
                            objectEntries!.append((grabbingKey, grabbedText))
                            return "$COMPLETE_OBJECT"
                        }
                        return grabbedText
                    }
                    if isGrabbingNotation { grabbedText.append(char) }
                    
                    // occur after all element in foccused array or object is finished searching...
                    if notationBalance == processedPathIndex {
                        if isCountArray {
                            // occur when when not matching element is found for given array index and array finished iterating...
                            if isGrabbingMultipleValues {
                                arrayValues!.append(grabbedText)
                                return "$COMPLETE_ARRAY"
                            }
                            return nil
                        }
                        // exit occur after no matching key is found in object
                        if char == "}" && !startSearchValue {
                            if copyObjectEntries { return "$COMPLETE_OBJECT" }
                            return nil
                        }
                        
                        // occur after finishing copy json notation
                        if processedPathIndex == paths.count {
                            if !copyObjectEntries { return grabbedText }
                            objectEntries!.append((grabbingKey, grabbedText))
                            startSearchValue = false
                            isGrabbingNotation = false
                            processedPathIndex -= 1
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
            
            // isGrabbingMultipleValues is flag to capture all elements in array
            if isGrabbingMultipleValues {
                // after each element in array level there would be ',' character
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
                            if !copyObjectEntries { return grabbedText }
                            objectEntries!.append((grabbingKey, grabbedText))
                            startSearchValue = false
                            processedPathIndex -= 1
                        } else {
                            grabbedText = ""
                        }
                        // used to copy values true, false, null and number
                    } else if !isInQuotes && !isGrabbingText && (char.isNumber || char == "n" || char == "f" || char == "t") {
                        grabbedText = ""
                        grabbedText.append(char)
                        isGrabbingText = true
                        continue
                    } else if isGrabbingText {
                        if !isInQuotes && char == "," {
                            if !copyObjectEntries { return grabbedText }
                            objectEntries!.append((grabbingKey, grabbedText))
                            startSearchValue = false
                            isGrabbingText = false
                            processedPathIndex -= 1
                        }
                        grabbedText.append(char)
                        continue
                    }
                }
                // section responsible for finding matching key in object notation
            } else {
                // grabbing the matching correct object key as given in path
                if (processedPathIndex + 1) == notationBalance && char == "\"" {
                    isGrabbingKey = !isGrabbingKey
                    isInQuotes = !isInQuotes
                    if !isGrabbingKey {
                        // if found start searching for object value for object key
                        if (copyObjectEntries && (processedPathIndex + 1) == paths.count) || grabbingKey == paths[processedPathIndex] {
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
