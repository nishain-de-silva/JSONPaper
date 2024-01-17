//
//  File.swift
//
//
//  Created by Nishain De Silva on 2023-06-11.
//
internal struct TypeConstraint {
    private let requiredType: String?
    private let canStringParse: Bool
    
    init() {
        canStringParse = false
        requiredType = nil
    }
    
    init(_ requiredType: String?, canStringParse: Bool) {
        self.canStringParse = canStringParse
        self.requiredType = requiredType
    }
    
    func isTypeMatch(_ type: String) -> Bool {
        return requiredType == nil
            || requiredType == type
            || (canStringParse && type == "string")
    }
}

internal class Base: State {
    internal enum UpdateMode {
        case upsert
        case onlyUpdate
        case onlyInsert
        case delete
    }
    
    internal class ValueStore {
        var string: String = ""
        var memoryHolder: [UInt8] = []
        
        var array: [JSONBlock] = []
        var children = JSONCollection()
        var tree: Any = []
        var isBytes: Bool = false
        
        init(_ input: String) {
            string = input
        }
        
        init(_ data: [UInt8]) {
            memoryHolder = data
            isBytes = true
        }
        
        init(_ text: String, _ data: [UInt8]) {
            string = text
            memoryHolder = data
            isBytes = !memoryHolder.isEmpty
        }
        
        init(arrayData: [JSONBlock]) {
            array = arrayData
        }
        
        init(childData: JSONCollection) {
            children = childData
        }
        
        init(parsedData: Any) {
            tree = parsedData
        }
    }
    
    internal static func serializeToBytes(_ node: Any?, _ stringDelimiter: UInt8) -> [UInt8]  {
        if let node {
            guard let object = node as? [String: Any?] else {
                guard let array = node as? [Any?] else {
                    guard let string = node as? String else {
                        guard let boolean =  node as? Bool else {
                            guard let intNumber = node as? Int else {
                                guard let doubleNumber = node as? Double else {
                                    guard let jsonEntity = node as? JSONBlock else {
                                        return [stringDelimiter, 35, 73, 78, 86, 65, 76, 73, 68, 95, 84, 89, 80, 69, stringDelimiter] // "#INVALID_TYPE"
                                    }
                                    return jsonEntity.base.jsonDataMemoryHolder
                                }
                                return Array(String(doubleNumber).utf8)
                            }
                            return Array(String(intNumber).utf8)
                        }
                        return boolean ? [116, 114, 117, 101] : [102, 97, 108, 115, 101]
                    }
                    return [stringDelimiter] + Array(string.utf8) + [stringDelimiter]
                }
                let innerContent = array.map({serializeToBytes($0, stringDelimiter)})
                
                return ([91] + innerContent.joined(separator: [44])) + [93]
            }
            let innerContent = object.map({(key, value) in
                (([stringDelimiter] + Array(key.utf8)) + [stringDelimiter, 58]) + serializeToBytes(value, stringDelimiter)
            })
            
            return ([123] + (innerContent.joined(separator: [44]))) + [125]
        } else {
            return [110, 117, 108, 108]
        }
    }
    
    
    private func replaceData(_ iterator: inout PeekIterator, _ data: [UInt8], copiedBytes: inout [UInt8]) {
        
        let quotation = quotation
        // 0 - object/array, string - 1, others - 3
        var notationBalance = 0
        var type = -1
        var isInQuotes = false
        var isEscaping = false
        
        while iterator.hasNext() {
            let char = iterator.next()
            if char == 123 || char == 91 {
                type = 1
                notationBalance = 1
                break
            }
            if char == quotation {
                type = 2
                isInQuotes = true
                break
            }
            if (char > 47 && char < 58) || char == 45 || (char > 96 && char < 123) {
                type = 3
                break
            }
            if char > 32 {
                copiedBytes.append(char)
            }
        }
        
        if type == 1 || type == 2 {
            while iterator.hasNext() {
                let char = iterator.next()
                if isInQuotes {
                    if !isEscaping && char == quotation {
                        if type == 2 {
                            copiedBytes.append(contentsOf: data)
                            return
                        }
                        isInQuotes = false
                        
                    } else if isEscaping {
                        isEscaping = false
                    } else if char == 92 {
                        isEscaping = true
                    }
                } else {
                    if char == 123 || char == 91 {
                        notationBalance += 1
                    } else if char == 125 || char == 93 {
                        notationBalance -= 1
                        if notationBalance == 0 {
                            copiedBytes.append(contentsOf: data)
                            return
                        }
                    } else if char == quotation {
                        isInQuotes = true
                    }
                }
                
            }
        } else if type == 3 {
            while iterator.hasNext() {
                let char = iterator.next()
                if !(isNumber(char) || (char > 96 && char < 123)) {
                    copiedBytes.append(contentsOf: data)
                    iterator.moveBack()
                    return
                }
            }
        }
    }
    
    internal func isNumber(_ char: UInt8) -> Bool {
        return (char > 47 && char < 58) || char == 46 || char == 45
    }
    
    internal func getField <T>(_ path: String?, _ fieldName: String, _ mapper: (ValueStore) -> T?, ignoreType:Bool = false) -> T? {
        if let path {
            guard let result = decodeData(path, typeConstraint: TypeConstraint(fieldName, canStringParse: ignoreType))
            else { return nil }
            return mapper(result.value)
        }
        
        if TypeConstraint(fieldName, canStringParse: ignoreType)
            .isTypeMatch(contentType) {
            return mapper(ValueStore(jsonText, jsonDataMemoryHolder))
        }
        if errorHandler != nil {
            errorHandler!(ErrorInfo(ErrorCode.nonMatchingDataType, -1, ""))
            errorHandler = nil
        }
        return nil
    }
    
    internal func resolveValue(_ stringData: String, _ byteData: [UInt8], _ type: String) -> Any {
        switch(type) {
            case "number": return Double(stringData) ?? "#INVALID_NUMERIC"
            case "array": return JSONBlock(byteData, "array").collection()!
            case "boolean": return stringData == "true" ? true : false
            case "null": return Constants.NULL
            default: return stringData
        }
    }
    
    @discardableResult
    private func addData(_ notationBalance: Int, _ isInObject: Bool, _ data: [UInt8], _ copiedBytes: inout [UInt8], paths: [[UInt8]], isIntermediateAdd: Bool = false) -> (ErrorCode, Int)? {
        
        let quotation = quotation
        if !isIntermediateAdd {
            copiedBytes.removeLast()
            if !(copiedBytes.last == 123 || copiedBytes.last == 91) {
                copiedBytes.append(44)
            }
        }
        
        if isInObject {
            copiedBytes.append(quotation)
            copiedBytes.append(contentsOf: paths[paths.count - 1])
            copiedBytes.append(contentsOf: [quotation, 58])
        }

        copiedBytes.append(contentsOf: data)
        if isIntermediateAdd {
            copiedBytes.append(44)
        } else {
            copiedBytes.append(isInObject ? 125 : 93)
        }
        return nil
    }
    
    internal func handleWrite(_ path: String, _ data: Any?, _ mode: UpdateMode, _ multiple: Bool) {
        write(path, Base.serializeToBytes(data, quotation), writeMode: mode, multiple)
        if errorInfo != nil {
            errorHandler?(ErrorInfo(errorInfo!.code, errorInfo!.occurredQueryIndex, path))
            errorHandler = nil
        }
    }
    
    internal func write(_ inputPath: String,
            _ data: [UInt8], writeMode: UpdateMode,
            _ isMultiple: Bool
        ) {
        errorInfo = nil
        if !(contentType == "object" || contentType == "array") {
            errorInfo = (ErrorCode.nonNestableRootType, 0)
            return
        }
        
        let (paths, lightMatch, arrayIndexes, searchDepths) = splitPath(inputPath)
        var processedPathIndex = 0
        var advancedOffset = 0
        var traversalHistory: [(processedPathIndex: Int, advancedOffset: Int)] = []

        var isInQuotes = false
        var startSearchValue = false
        var grabbingKey:[UInt8] = []
        var copiedBytes: [UInt8] = []
        var needProcessKey = false
        var isGrabbingKey = false
        var isObjectAttributeFound = false
    
        var notationBalance = 0
        var searchDepth = 1
        var escapeCharacter: Bool = false

        @discardableResult
        func restoreLastPointIfNeeded(_ shouldRestore: Bool = true) -> Bool {
            if shouldRestore && traversalHistory.count > 0 {
                (processedPathIndex, advancedOffset) =  traversalHistory[traversalHistory.count - 1]
                searchDepth = searchDepths[processedPathIndex]
                startSearchValue = false
                return true
            }
            return false
        }
        
        func addToTraversalHistoryIfNeeded() {
            if searchDepths[processedPathIndex] == 0 {
                traversalHistory.append((processedPathIndex, advancedOffset))
            }
            searchDepth = searchDepths[processedPathIndex]
        }
        
        func isAttributeKeyMatch(_ lightMatch: Int, _ capturedKey: [UInt8], _ keyToMatch: [UInt8]) -> Bool {
            if lightMatch < 3 {
                return capturedKey == keyToMatch
            }
            var searchIndex = 0
            for char in capturedKey {
                if char == keyToMatch[searchIndex] {
                    searchIndex += 1
                    if searchIndex == keyToMatch.count {
                        return true
                    }
                }
            }
            return false
        }
        
        func finishWriting() {
            let quotation = quotation
            while iterator.hasNext() {
                let char = iterator.next()
                if isInQuotes || char > 32 {
                    copiedBytes.append(char)
                }
                if !escapeCharacter && char == quotation {
                    isInQuotes = !isInQuotes
                } else if isInQuotes {
                    if escapeCharacter {
                        escapeCharacter = false
                    } else if char == 92 {
                        escapeCharacter = true
                    }
                }
            }
            
            jsonDataMemoryHolder = copiedBytes
            jsonData = jsonDataMemoryHolder.withUnsafeBytes({$0})
        }
        
        
        if paths.count == 0 {
            errorInfo = (ErrorCode.emptyQueryPath, -1)
            return
        }
        
        if paths.last == intermediateSymbol {
            errorInfo = (ErrorCode.captureUnknownElement, paths.count - 1)
            return
        }
        
        let quotation = quotation
        
        var iterator = PeekIterator(jsonData)
        
        addToTraversalHistoryIfNeeded()
        
        while iterator.hasNext() {
            let char = iterator.next()
            if isInQuotes || char > 32 {
                copiedBytes.append(char)
            }
            // if within quotation ignore processing json literals...
            if !isInQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                    
                    // initiate elements counting inside array on reaching open bracket...
                    if char == 91 && (searchDepth == 0 || (advancedOffset + searchDepth) == notationBalance) {
                        let parsedIndex = arrayIndexes[processedPathIndex]
                        // occur when trying to access element of array with non-number index
                        if parsedIndex == nil {
                            if restoreLastPointIfNeeded() {
                                continue
                            }
                            errorInfo = (ErrorCode.invalidArrayIndex, processedPathIndex)
                            return
                        }
                        
                        if (processedPathIndex + 1) == paths.count {
                            if iterateArrayWriteRecursive(&iterator, elementIndex: parsedIndex!, &copiedBytes, notationBalance, searchDepth == 0, data, writeMode, isMultiple) {
                                if !restoreLastPointIfNeeded(isMultiple) {
                                    finishWriting()
                                    return
                                }
                            }
                        } else {
                            if iterateArrayWrite(&iterator, elementIndex: parsedIndex!, &copiedBytes) {
                                processedPathIndex += 1
                                advancedOffset += searchDepth
                                if searchDepth == 0 {
                                    advancedOffset = notationBalance
                                }
                                startSearchValue = true
                                addToTraversalHistoryIfNeeded()
                            }
                        }
                    } else {
                        // move to next nest object and start looking attribute key on next nested object...
                        startSearchValue = false
                    }
                    continue
                }
                
                if char == 125 || char == 93 {
                    notationBalance -= 1
                    // section responsible for adding attribute at the end of the object if the attribute is not found
                    if (searchDepth == 0 || notationBalance == advancedOffset) && char == 125 && (processedPathIndex + 1) == paths.count && (writeMode == .upsert || writeMode == .onlyInsert) {
                        if isObjectAttributeFound {
                            isObjectAttributeFound = false
                        } else {
                            // make sure the the last attribute is an object attribute and not an array index
                            if arrayIndexes[arrayIndexes.count - 1] == nil {
                                addData(notationBalance + 1, true, data, &copiedBytes, paths: paths)
                                if !restoreLastPointIfNeeded(isMultiple) {
                                    finishWriting()
                                    return
                                }
                            } else if !restoreLastPointIfNeeded() {
                                errorInfo = (ErrorCode.objectKeyNotFound, paths.count - 1)
                                return
                            }
                        }
                    }
                    
                    // occur after all element in focused array or object is finished searching...
                    if notationBalance == advancedOffset {
                        if traversalHistory.count != 0 {
                            if traversalHistory.last!.advancedOffset == advancedOffset {
                                let lastIndex = traversalHistory.removeLast().processedPathIndex
                                
                                if traversalHistory.count == 0 {
                                    if isMultiple {
                                        finishWriting()
                                        return
                                    }
                                    errorInfo = (ErrorCode.cannotFindElement, lastIndex)
                                    return
                                }
                            }
                            (processedPathIndex, advancedOffset) = traversalHistory.last!
                            searchDepth = searchDepths[processedPathIndex]
                            startSearchValue = false
                            continue
                        }
                        // checking wether if currently the processing index is attribute or array index
                        errorInfo = (arrayIndexes[processedPathIndex] == nil ? ErrorCode.objectKeyNotFound : ErrorCode.arrayIndexNotFound, notationBalance)
                        return
                    }
                    continue
                }
            }
            
            // ======== FINISHED HANDING JSON OPEN AND CLOSE NOTATION ==========
            if startSearchValue {
                if notationBalance == advancedOffset {
                    // ====== HANDLING GRABBING STRINGS =========
                    // ignore escaped double quotation characters inside string values...
                    if !escapeCharacter && char == quotation {
                        isInQuotes = !isInQuotes
                        // if not the last processed value skip capturing value
                        if processedPathIndex != paths.count {
                            if restoreLastPointIfNeeded() {
                                continue
                            }
                            errorInfo = (ErrorCode.nonNestedParent, processedPathIndex - 1)
                            return
                        }
                        // used to copy values true, false, null and number
                    } else {
                        // ========== HANDLING GRABBING NUMBERS, BOOLEANS AND NULL
                        if !isInQuotes && ((char >= 48 && char <= 57) || char == 45
                                || char == 116 || char == 102
                                || char == 110
                        ) {
                            if processedPathIndex != paths.count {
                                if restoreLastPointIfNeeded() {
                                    continue
                                }
                                errorInfo = (ErrorCode.nonNestedParent, processedPathIndex - 1)
                                return
                            }
                        }
                    }
                } else if char == quotation && !escapeCharacter {
                    isInQuotes = !isInQuotes
                }
                
                // ========= SECTION RESPONSIBLE HANDLING OBJECT KEY
            } else {
                if char == quotation && !escapeCharacter {
                    isInQuotes = !isInQuotes
                    // grabbing the matching correct object key as given in path
                    if searchDepth == 0 || (advancedOffset + searchDepth) == notationBalance {
                        isGrabbingKey = isInQuotes
                        if isGrabbingKey {
                            grabbingKey = []
                        } else {
                            needProcessKey = true
                        }
                    }
                } else if isGrabbingKey {
                    // section for accumulating characters for attribute key when light search is active
                    if lightMatch[processedPathIndex] != 1 {
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
                    if isAttributeKeyMatch(lightMatch[processedPathIndex], grabbingKey, paths[processedPathIndex]) && arrayIndexes[processedPathIndex] == nil {
                        processedPathIndex += 1
                        advancedOffset += searchDepth
                        if searchDepth == 0 {
                            advancedOffset = notationBalance
                        }
                        startSearchValue = true
                        
                        // section responsible to when last attribute is found
                        if(processedPathIndex == paths.count) {
                            if writeMode == .delete {
                                deleteData(&iterator, &copiedBytes, notationBalance)
                                if restoreLastPointIfNeeded(isMultiple) { continue } else {
                                    finishWriting()
                                    return
                                }
                            } else if writeMode == .onlyInsert {
                                if restoreLastPointIfNeeded() {
                                    isObjectAttributeFound = true
                                    continue
                                }
                                errorInfo = (ErrorCode.objectKeyAlreadyExists, processedPathIndex - 1)
                                return
                            } else {
                                replaceData(&iterator, data, copiedBytes: &copiedBytes)
                                if writeMode == .upsert {
                                    isObjectAttributeFound = true
                                }
                                if restoreLastPointIfNeeded(isMultiple) { continue } else {
                                    finishWriting()
                                    return
                                }
                            }
                        } else {
                            addToTraversalHistoryIfNeeded()
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
        return
    }

    private func deleteData(_ iterator: inout PeekIterator, _ copiedData: inout [UInt8], _ prevNotationBalance: Int) {
        var didRemovedFirstComma = false
        var isInQuotes = false
        var notationBalance = prevNotationBalance
        var escapeCharacter = false
        
        let quotation = quotation
        
        while iterator.hasNext() {
            guard let char = copiedData.last else { break }
            if !escapeCharacter && char == quotation {
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
        
        while iterator.hasNext() {
            let char = iterator.next()
            if !escapeCharacter && char == quotation {
                isInQuotes = !isInQuotes
            }
            if !isInQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if notationBalance == (prevNotationBalance - 1) {
                        iterator.moveBack()
                        return
                    }
                } else if char == 44 && notationBalance == prevNotationBalance {
                    if didRemovedFirstComma {
                        copiedData.append(44)
                    }
                    return
                }
            }
            
            if escapeCharacter {
                escapeCharacter = false
            } else if char == 92 {
                escapeCharacter = true
            }
        }
    }
    
    private func parseSingularValue(_ input: String) -> Any? {
        if input.first == "t" {
            return true
        } else if input.first == "f" {
            return false
        } else if input.first == "n" {
            return nil
        } else {
            return Double(input) ?? "#INVALID_NUMERIC"
        }
    }
    
    private func parseNextElement(_ iterator: inout PeekIterator, firstCharacter: UInt8, _ quotation: UInt8) -> Any {
        var isEscaping = false
        var objectValue: [String: Any?] = [:]
        var arrayValue: [Any?] = []
        var grabbedKey = ""
        var grabbedText = ""
        let isObject = firstCharacter == 123
        var isKeyCaptured = false
        var isInQuotes = false
        while iterator.hasNext() {
            let char = iterator.next()
            if !isEscaping && char == quotation {
                isInQuotes = !isInQuotes
                if isInQuotes {
                    // inside a array no need to worry about keys...
                    grabbedText = ""
                } else {
                    if isObject {
                        if isKeyCaptured {
                            objectValue[grabbedKey] = grabbedText
                            isKeyCaptured = false
                        } else {
                            grabbedKey = grabbedText
                            isKeyCaptured = true
                        }
                    } else {
                        arrayValue.append(grabbedText)
                    }
                }
            } else if isInQuotes {
                if isEscaping {
                    isEscaping = false
                } else if char == 92 {
                    isEscaping = true
                }
                grabbedText.append(Character(UnicodeScalar(char)))
            } else {
                if char == 123 || char == 91 {
                    if isObject {
                        objectValue[grabbedKey] = parseNextElement(&iterator, firstCharacter: char, quotation)
                        isKeyCaptured = false
                    } else {
                        arrayValue.append(parseNextElement(&iterator, firstCharacter: char, quotation))
                    }
                } else if char == 125 || char == 93 {
                    if isObject { return objectValue }
                    return arrayValue
                } else {
                    guard let value = getPrimitive(&iterator, char)?.value else { continue }
                    if isObject {
                        objectValue[grabbedKey] = parseSingularValue(value)
                        isKeyCaptured = false
                    } else {
                        arrayValue.append(parseSingularValue(value))
                    }
                }
            }
            
        }
        return "#INVALID_TYPE"
    }
    
    internal func getStructuredData(_ iterator: inout PeekIterator, firstCharacter: UInt8) -> (value: ValueStore, type: String) {
        let dataType = firstCharacter == 123 ? "object" : "array"
        return (
            ValueStore(parsedData:
                        parseNextElement(
                            &iterator,
                            firstCharacter: firstCharacter,
                            quotation
                        )
                    ), dataType)
    }
        
    private func iterateArray(_ iterator: inout PeekIterator, elementIndex: Int) -> Bool {
        var notationBalance = 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        
        if elementIndex == 0 {
            guard let nextChar = iterator.peek() else { return false }
            return nextChar != 93
        }
        
        let quotation = quotation
        
        while iterator.hasNext() {
            let char = iterator.next()
            if !escapeCharacter && char == quotation {
                isQuotes = !isQuotes
            }
            if !isQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if notationBalance == 0 {
                        iterator.moveBack()
                        return false
                    }
                } else if char == 44 && notationBalance == 1 {
                    cursorIndex += 1
                    if cursorIndex == elementIndex {
                        return true
                    }
                }
            }
            if escapeCharacter {
                escapeCharacter = false
            } else if char == 92 {
                escapeCharacter = true
            }
        }
        return false
    }
    
    private func iterateArrayWrite(_ iterator: inout PeekIterator, elementIndex: Int, _ copyingData: inout [UInt8]) -> Bool {
        var notationBalance = 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        
        if elementIndex == 0 {
            guard let nextChar = iterator.peek() else { return false }
            return nextChar != 93
        }
        
        let quotation = quotation
        
        while iterator.hasNext() {
            let char = iterator.next()
            
            if !escapeCharacter && char == quotation {
                isQuotes = !isQuotes
            }
            if !isQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if notationBalance == 0 {
                        iterator.moveBack()
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
            if escapeCharacter {
                escapeCharacter = false
            } else if char == 92 {
                escapeCharacter = true
            }
            copyingData.append(char)
        }
        return false
    }
    
    private func iterateArrayWriteRecursive(_ iterator: inout PeekIterator, elementIndex: Int, _ copyingData: inout [UInt8], _ initialNotationBalance: Int, _ shouldRecurse: Bool, _ data: [UInt8], _ updateMode: UpdateMode, _ isMultiple: Bool) -> Bool {
        var notationBalance = initialNotationBalance
        let stopBalance = initialNotationBalance - 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        var didProcessed = false
        
        let quotation = quotation
        
        if elementIndex == 0 {
            guard let char = iterator.peek() else { return false }
            
            if char == 93 {
                copyingData.append(char)
                if updateMode == .onlyInsert || updateMode == .upsert {
                    addData(notationBalance, false, data, &copyingData, paths: [])
                    copyingData.removeLast()
                    return true
                }
                copyingData.removeLast()
                return false
            }
            if updateMode == .delete {
                deleteData(&iterator, &copyingData, notationBalance)
            } else if updateMode == .onlyInsert {
                addData(notationBalance, false, data, &copyingData, paths: [], isIntermediateAdd: true)
            } else {
                replaceData(&iterator, data, copiedBytes: &copyingData)
            }
            return true
        }
        
        while iterator.hasNext() {
            let char = iterator.next()
            copyingData.append(char)
            if !escapeCharacter && char == quotation {
                isQuotes = !isQuotes
            }
            if !isQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                    if char == 91 && shouldRecurse {
                        didProcessed = iterateArrayWriteRecursive(&iterator, elementIndex: elementIndex, &copyingData, notationBalance, true, data, updateMode, isMultiple)
                        if !isMultiple && didProcessed {
                            return true
                        }
                    }
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if notationBalance == stopBalance {
                        iterator.moveBack()
                        if updateMode == .onlyInsert || updateMode == .upsert {
                            addData(notationBalance + 1, false, data, &copyingData, paths: [])
                            copyingData.removeLast()
                            return true
                        }
                        copyingData.removeLast()
                        return didProcessed
                    }
                } else if char == 44 && notationBalance == initialNotationBalance {
                    cursorIndex += 1
                    if cursorIndex == elementIndex {
                        if updateMode == .delete {
                            deleteData(&iterator, &copyingData, notationBalance)
                        } else if updateMode == .onlyInsert {
                            addData(notationBalance, false, data, &copyingData, paths: [], isIntermediateAdd: true)
                        } else {
                            let replacingData = Base.serializeToBytes(data, quotation)
                            replaceData(&iterator, replacingData, copiedBytes: &copyingData)
                        }
                        return true
                    }
                }
            }
            
            if escapeCharacter {
                escapeCharacter = false
            } else if char == 92 {
                escapeCharacter = true
            }
        }
        return false
    }
    
    internal func getKeys() -> [String]? {
        if contentType != "object" {
            errorHandler?(ErrorInfo(ErrorCode.cannotFindObjectKeys, -1, ""))
            errorHandler = nil
            return nil
        }
        
        var isInQuotes = false
        var isEscaped = false
        var grabbedBytes: [UInt8] = []
        var notationBalance = 0
        var keys: [String] = []
        
        for char in jsonData {
            if !isEscaped && char == quotation {
                isInQuotes = !isInQuotes
                if isInQuotes && notationBalance == 1 {
                    grabbedBytes = []
                }
            } else if isInQuotes  {
                if isEscaped {
                    isEscaped = false
                } else if char == 92 {
                    isEscaped = true
                }
                if notationBalance == 1 {
                    grabbedBytes.append(char)
                }
            } else if char == 123 || char == 91 {
                notationBalance += 1
            } else if char == 125 || char == 93 {
                notationBalance -= 1
            } else if char == 58 && notationBalance == 1 {
                keys.append(String(
                    grabbedBytes.map({ Character(UnicodeScalar($0)) })
                ))
            }
        }
        return keys
    }

    private func getNextElement(_ iterator: inout PeekIterator, _ quotation: UInt8, _ isCopyCollection: Bool) -> (value: ValueStore, type: String) {
        var text = ""
        var data: [UInt8] = []
        while iterator.hasNext() {
            let char = iterator.next()
            if char == quotation {
                var isEscape = false
                while iterator.hasNext() {
                    let stringChar = iterator.next()
                    if !isEscape && stringChar == quotation {
                        return (ValueStore(text), "string")
                    }
                    if isEscape {
                        isEscape = false
                    } else if stringChar == 92 {
                        isEscape = true
                    }
                    text.append(Character(UnicodeScalar(stringChar)))
                }
            } else if char == 123 || char == 91 {
                if extractInnerContent {
                    return getStructuredData(&iterator, firstCharacter: char)
                } else if isCopyCollection {
                    if char == 123 {
                        return (ValueStore(childData: JSONCollection(getObjectEntries(&iterator), isArray: false)), "CODE_COLLECTION")
                    } else {
                        return (ValueStore(childData: JSONCollection(getArrayValues(&iterator), isArray: true)), "CODE_COLLECTION")
                    }
                }
                data = [char]
                grabData(&data, &iterator)
                return (ValueStore(data), char == 123 ? "object" : "array")
            } else {
                let result = getPrimitive(&iterator, char)
                if let result {
                    return (ValueStore(result.value), result.dataType)
                }
            }
        }
        return (ValueStore("no data to retrieve"), "string")
    }
    
    private func iterateArrayRecursive(_ iterator: inout PeekIterator, elementIndex: Int, _ initialNotationBalance: Int, _ values: inout [JSONBlock], _ shouldRecurse: Bool, _ mode: Int, _ typeConstraint: TypeConstraint) -> (ValueStore, String)? {
        var notationBalance = initialNotationBalance
        let stopBalance = initialNotationBalance - 1
        var escapeCharacter = false
        var isQuotes = false
        var cursorIndex = 0
        var innerItem: (ValueStore, String)? = nil
        
        let quotation = quotation
        if elementIndex == 0 {
            guard let char = iterator.peek() else { return nil }
            if char == 93 {
                return nil
            }
            /*
                mode 0 - singular value
                mode 1 - collection data
                mode 2 - multiple data
             */
            let result = getNextElement(&iterator, quotation, mode == 1)
            if mode < 2 {
                if typeConstraint.isTypeMatch(result.type) { return result }
                return nil
            }
            if typeConstraint.isTypeMatch(result.type) {
                if result.value.isBytes {
                    values.append(JSONBlock(result.value.memoryHolder, result.type, self))
                } else {
                    values.append(JSONBlock(result.value.string, result.type))
                }
                return nil
            }
        }
        
        while iterator.hasNext() {
            let char = iterator.next()
            if !escapeCharacter && char == quotation {
                isQuotes = !isQuotes
            }
            if !isQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                    if char == 91 && shouldRecurse {
                        innerItem = iterateArrayRecursive(&iterator, elementIndex: elementIndex, notationBalance, &values, true, mode, typeConstraint)
                        // if innerItem is nil then it means this is a multiple data read
                        if let innerItem {
                            return innerItem
                        }
                    }
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    if notationBalance == stopBalance {
                        iterator.moveBack()
                        return nil
                    }
                } else if char == 44 && notationBalance == initialNotationBalance {
                    cursorIndex += 1
                    if cursorIndex == elementIndex {
                        let result = getNextElement(&iterator, quotation, mode == 1)
                        if mode < 2 {
                            if typeConstraint.isTypeMatch(result.type) { return result }
                            return nil
                        }
                        if typeConstraint.isTypeMatch(result.type) {
                            if result.value.isBytes {
                                values.append(JSONBlock(result.value.memoryHolder, result.type, self))
                            } else {
                                values.append(JSONBlock(result.value.string, result.type))
                            }
                            return nil
                        }
                    }
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

    
    private func grabData(_ copiedData: inout [UInt8], _ iterator: inout PeekIterator) {
        var notationBalance = 1
        var isQuotes = false
        var isEscape = false
        
        let quotation = quotation
        while iterator.hasNext() {
            let char = iterator.next()
            if !isEscape && char == quotation {
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
    
    private func getObjectEntries(_ iterator: inout PeekIterator) -> [JSONChild] {
        var values: [JSONChild] = []
        var bytes: [UInt8] = []
        var text: String = ""
        var dataType = ""
        var isQuotes = false
        var grabbedKey = ""
        var isEscaping = false
        var shouldGrabItem = false
        
        let quotation = quotation
        while iterator.hasNext() {
            let char = iterator.next()
             if !isEscaping && char == quotation {
                isQuotes = !isQuotes
                if isQuotes {
                    text = ""
                    continue
                } else {
                    if shouldGrabItem {
                        shouldGrabItem = false
                        values.append(JSONChild(text, "string", self).setKey(grabbedKey))
                    }
                }
            } else if !isQuotes {
                if char == 123 || char == 91 {
                    bytes = [char]
                    dataType = char == 123 ? "object" : "array"
                    grabData(&bytes, &iterator)
                    values.append(JSONChild(bytes, dataType, self).setKey(grabbedKey))
                    shouldGrabItem = false
                    continue
                }
                if shouldGrabItem {
                    if let result = getPrimitive(&iterator, char) {
                        values.append(JSONChild(result.value, result.dataType, self).setKey(grabbedKey))
                        shouldGrabItem = false
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

    
    private func getArrayValues(_ iterator: inout PeekIterator) -> [JSONChild] {
        var values: [JSONChild] = []
        var bytes: [UInt8] = []
        var text: String = ""
        var dataType = ""
        var isQuotes = false
        var isEscaping = false
        var index = 0
        
        let quotation = quotation
        while iterator.hasNext() {
            let char = iterator.next()
            if !isEscaping && char == quotation {
                isQuotes = !isQuotes
                if isQuotes {
                    text = ""
                    continue
                } else {
                    values.append(JSONChild(text, "string", self).setIndex(index))
                    index += 1
                }
            } else if !isQuotes {
                if char == 123 || char == 91 {
                    bytes = [char]
                    dataType = char == 123 ? "object" : "array"
                    grabData(&bytes, &iterator)
                    values.append(JSONChild(bytes, dataType, self).setIndex(index))
                    index += 1
                    continue
                }
                if let result = getPrimitive(&iterator, char) {
                    values.append(JSONChild(result.value, result.dataType, self).setIndex(index))
                    index += 1
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
    
    private func getPrimitive(_ iterator: inout PeekIterator, _ firstCharacter: UInt8) -> (dataType: String, value: String)? {
        if firstCharacter == 116 {
            return ("boolean", "true")
        } else if firstCharacter == 102 {
            return ("boolean", "false")
        } else if firstCharacter == 110 {
            return ("null", "null")
        } else if (firstCharacter > 47 && firstCharacter < 58) || firstCharacter == 45 {
            var copiedNumber = "\(Character(UnicodeScalar(firstCharacter)))"
            while iterator.hasNext() {
                let num = iterator.next()
                if (num > 47 && num < 58) || num == 46 {
                    copiedNumber.append(Character(UnicodeScalar(num)))
                } else {
                    if num == 125 || num == 93 {
                        iterator.moveBack()
                    }
                    break
                }
            }
            return ("number", copiedNumber)
        }
        return nil
    }
    
    private func singleItemList(_ source: JSONBlock) -> (ValueStore, String) {
        return (ValueStore(arrayData: [source]), "CODE_ALL")
    }
    
    private func exploreData(_ inputPath: String,
     _ copyCollectionData: Bool, _ grabAllPaths: Bool, _ typeConstraint: TypeConstraint
        ) -> (value: ValueStore, type: String)? {
        errorInfo = nil
        if !(contentType == "object" || contentType == "array") {
            errorInfo = (ErrorCode.nonNestableRootType, 0)
            return nil
        }
        let (paths, lightMatch, arrayIndexes, searchDepths) = splitPath(inputPath)
        var processedPathIndex = 0
        var advancedOffset = 0
        var traversalHistory: [(processedPathIndex: Int, advancedOffset: Int)] = []

        var isInQuotes = false
        var startSearchValue = false
        var grabbingKey:[UInt8] = []
        var needProcessKey = false
        var isGrabbingKey = false
        var searchDepth = 1
        var notationBalance = 0
        var escapeCharacter: Bool = false
        var commonPathCollections: [JSONBlock] = []
        
        /*
            mode 0 - singular value
            mode 1 - collection data
            mode 2 - multiple data
         */
        var extractMode = 0
        if grabAllPaths {
            extractMode = 2
        } else if copyCollectionData {
            extractMode = 1
        }
        
        func restoreLastPointIfNeeded() -> Bool {
            if traversalHistory.count > 0 {
                (processedPathIndex, advancedOffset) =  traversalHistory[traversalHistory.count - 1]
                searchDepth = searchDepths[processedPathIndex]
                startSearchValue = false
                return true
            }
            return false
        }
        
        func isAttributeKeyMatch(_ lightMatch: Int, _ capturedKey: [UInt8], _ keyToMatch: [UInt8]) -> Bool {
            if lightMatch < 3 {
                return capturedKey == keyToMatch
            }
            var searchIndex = 0
            for char in capturedKey {
                if char == keyToMatch[searchIndex] {
                    searchIndex += 1
                    if searchIndex == keyToMatch.count {
                        return true
                    }
                }
            }
            return false
        }
        
        func addToTraversalHistoryIfNeeded() {
            if searchDepths[processedPathIndex] == 0 {
                traversalHistory.append((processedPathIndex, advancedOffset))
            }
            searchDepth = searchDepths[processedPathIndex]
        }
        
        let quotation = quotation
        
        if paths.count == 0 {
            if copyCollectionData {
                var iterator = PeekIterator(jsonData)
                return getNextElement(&iterator, quotation, true)
            }
            errorInfo = (ErrorCode.emptyQueryPath, -1)
            return nil
        }
        
        if paths.last == intermediateSymbol {
            errorInfo = (ErrorCode.captureUnknownElement, paths.count - 1)
            return nil
        }
        
        var iterator = PeekIterator(jsonData)
        
        addToTraversalHistoryIfNeeded()
        
        while iterator.hasNext() {
            let char = iterator.next()
            // if within quotation ignore processing json literals...
            if !isInQuotes {
                if char == 123 || char == 91 {
                    notationBalance += 1
                    // initiate elements counting inside array on reaching open bracket...
                    if char == 91 && (searchDepth == 0 || (advancedOffset + searchDepth) == notationBalance) {
                        let parsedIndex = arrayIndexes[processedPathIndex]
                        // occur when trying to access element of array with non-number index
                        if parsedIndex == nil {
                            if restoreLastPointIfNeeded() {
                                continue
                            }
                            errorInfo = (ErrorCode.invalidArrayIndex, processedPathIndex)
                            return nil
                        }
                        
                        if processedPathIndex == (paths.count - 1) {
                            var values: [JSONBlock] = []
                            let result = iterateArrayRecursive(&iterator, elementIndex: parsedIndex!, notationBalance, &values, searchDepth == 0, extractMode, typeConstraint)
                            if extractMode < 2 {
                                if result == nil {
                                    if restoreLastPointIfNeeded() { continue }
                                    errorInfo = (ErrorCode.arrayIndexNotFound, processedPathIndex)
                                    return nil
                                }
                                return result
                            }
                            if !values.isEmpty {
                                if !restoreLastPointIfNeeded() {
                                    return singleItemList(values[0])
                                }
                                commonPathCollections.append(contentsOf: values)
                            }
                        } else if iterateArray(&iterator, elementIndex: parsedIndex!) {
                            
                            advancedOffset += searchDepth
                            processedPathIndex += 1
                            if searchDepth == 0 {
                                advancedOffset = notationBalance
                            }
                            startSearchValue = true
                            addToTraversalHistoryIfNeeded()
                        }
                    } else {
                        // move to next nest object and start looking attribute key on next nested object...
                        startSearchValue = false
                    }
                    continue
                }
                
                if char == 125 || char == 93 {
                    notationBalance -= 1
                    // occur after all element in focused array or object is finished searching...
                    if notationBalance == advancedOffset {
                        if traversalHistory.count != 0 {
                            if traversalHistory.last!.advancedOffset == advancedOffset {
                                let lastIndex = traversalHistory.removeLast().processedPathIndex
                                
                                if traversalHistory.count == 0 {
                                    if grabAllPaths {
                                        return (ValueStore(arrayData: commonPathCollections), "CODE_ALL")
                                    }
                                    errorInfo = (ErrorCode.cannotFindElement, lastIndex)
                                    return nil
                                }
                            }
                            (processedPathIndex, advancedOffset) = traversalHistory.last!
                            searchDepth = searchDepths[processedPathIndex]
                            startSearchValue = false
                            continue
                        }
                        errorInfo = (arrayIndexes[processedPathIndex] == nil ? ErrorCode.objectKeyNotFound : ErrorCode.arrayIndexNotFound, notationBalance)
                        return nil
                        
                    }
                    
                    continue
                }
            } else {
                // handling escape characters at the end ...
                if escapeCharacter {
                    escapeCharacter = false
                } else if char == 92 {
                    escapeCharacter = true
                }
            }
            
            // ======== FINISHED HANDING JSON OPEN AND CLOSE NOTATION ==========
            if startSearchValue {
                if notationBalance == advancedOffset {
                    // ====== HANDLING GRABBING STRINGS =========
                    // ignore escaped double quotation characters inside string values...
                    if !escapeCharacter && char == quotation {
                        isInQuotes = !isInQuotes
                        // if not the last processed value skip capturing value
                        if processedPathIndex != paths.count {
                            if restoreLastPointIfNeeded() {
                                continue
                            }
                            errorInfo = (ErrorCode.nonNestedParent, processedPathIndex - 1)
                            return nil
                        }
                        // used to copy values true, false, null and number
                    } else {
                        // ========== HANDLING GRABBING NUMBERS, BOOLEANS AND NULL
                        if !isInQuotes {
                            if (char >= 48 && char <= 57) || char == 45
                                || char == 116 || char == 102
                                || char == 110 {
                                if processedPathIndex != paths.count {
                                    if restoreLastPointIfNeeded() {
                                        continue
                                    }
                                    errorInfo = (ErrorCode.nonNestedParent, processedPathIndex - 1)
                                    return nil
                                }
                            }
                        }
                    }
                } else if char == quotation && !escapeCharacter {
                    isInQuotes = !isInQuotes
                }
                
                // ========= SECTION RESPONSIBLE HANDLING OBJECT KEY
            } else {
                if char == quotation && !escapeCharacter {
                    isInQuotes = !isInQuotes
                    // grabbing the matching correct object key as given in path
                    if searchDepth == 0 || (advancedOffset + searchDepth) == notationBalance {
                        isGrabbingKey = isInQuotes
                        if isGrabbingKey {
                            grabbingKey = []
                        } else {
                            needProcessKey = true
                        }
                    }
                } else if isGrabbingKey {
                    if lightMatch[processedPathIndex] != 1 {
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
                    if isAttributeKeyMatch(lightMatch[processedPathIndex], grabbingKey, paths[processedPathIndex]) && arrayIndexes[processedPathIndex] == nil {
                        processedPathIndex += 1
                        advancedOffset += searchDepth
                        if searchDepth == 0 {
                            advancedOffset = notationBalance
                        }
                        startSearchValue = true
                        if processedPathIndex == paths.count {
                            let capturedElement = getNextElement(&iterator, quotation, copyCollectionData)
                            let isRestored = restoreLastPointIfNeeded()
                            
                            if !grabAllPaths {
                                if typeConstraint.isTypeMatch(capturedElement.type) {
                                    return capturedElement
                                }
                                if isRestored { continue }
                                errorInfo = (ErrorCode.objectKeyNotFound, processedPathIndex - 1)
                                return nil
                            }
                            if !typeConstraint.isTypeMatch(capturedElement.type) { continue }
                            
                            let elementToAdd: JSONBlock
                            if capturedElement.value.isBytes {
                                elementToAdd = JSONBlock(capturedElement.value.memoryHolder, capturedElement.type, self)
                            } else {
                                elementToAdd = JSONBlock(capturedElement.value.string, capturedElement.type)
                            }
                            if !isRestored {
                                return singleItemList(elementToAdd)
                            }
                            commonPathCollections.append(elementToAdd)
                        } else {
                            addToTraversalHistoryIfNeeded()
                        }
                    }
                }
            }
        }
        errorInfo = (ErrorCode.other, processedPathIndex)
        return nil
    }
    
    internal func identifyStringDelimiter(_ text: String) {
        for char in text {
            if char == "\"" || char == "'" {
                quotation = char == "\"" ? 34 : 39
                break
            }
        }
    }
    
    internal func prettifyContent(_ originalContent: UnsafeRawBufferPointer, _ tabSize: Int) -> String {
        var iterator = PeekIterator(originalContent)
        var presentation: [UInt8] = []
        var notationBalance = 0
        var isEscaping = false
        var isQuotes = false
        let quotation = quotation
        
        while iterator.hasNext() {
            let char = iterator.next()
            if !isEscaping && char == quotation {
                isQuotes = !isQuotes
            } else if !isQuotes {
                if char <= 32 {
                    continue
                } else if char == 123 || char == 91 {
                    if iterator.hasNext() {
                        let nextChar = iterator.next()
                        if nextChar == 125 || nextChar == 93 {
                            presentation.append(char)
                            presentation.append(nextChar)
                            continue
                        }
                        iterator.moveBack()
                    }
                    notationBalance += 1
                    presentation.append(char)
                    presentation.append(10)
                    presentation.append(contentsOf: [UInt8] (repeating: 32, count: notationBalance * tabSize))
                    continue
                } else if char == 125 || char == 93 {
                    notationBalance -= 1
                    presentation.append(10)
                    presentation.append(contentsOf: [UInt8] (repeating: 32, count: notationBalance * tabSize))
                } else if char == 44 {
                    presentation.append(char)
                    presentation.append(10)
                    presentation.append(contentsOf: [UInt8] (repeating: 32, count: notationBalance * tabSize))
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
        
        return asString(presentation)
    }
    
    internal func decodeData(_ inputPath:String, copyCollectionData: Bool = false, grabAllPaths: Bool = false, typeConstraint: TypeConstraint = TypeConstraint()) -> (value: ValueStore, type: String)? {
        let results = exploreData(inputPath, copyCollectionData, grabAllPaths, typeConstraint)
        if let errorInfo {
            errorHandler?(ErrorInfo(errorInfo.code, errorInfo.occurredQueryIndex, inputPath))
            errorHandler = nil
        }
        return results
    }
    
    private func getIntermediateSymbolDepthLimit(_ word: [UInt8]) -> Int? {
        var matchIndex = 0
        var stage = 0
        var index = 0
        for char in word {
            if stage == 0 && char == intermediateSymbol[matchIndex] {
                matchIndex += 1
                if matchIndex == intermediateSymbol.count {
                    stage = 1
                }
            } else if stage == 1 && char == 123 {
                stage = 2
            } else if stage > 1 && (char > 47 && char < 58) {
                index = (index * 10) + (Int(char) - 48)
                stage = 3
            } else if stage == 3 && char == 125 {
                return index == 0 ? 1 : index
            } else {
                return nil
            }
            
        }
        
        if stage == 1 {
            return 0
        }
        return nil
    }
    
    private func splitPath(_ path: String) -> (paths: [[UInt8]], lightMatch: [Int], arrayIndexes: [Int?], searchDepths: [Int]) {
        var paths: [[UInt8]] = []
        var lightMatch: [Int] = []
        var word: [UInt8] = []
        var arrayIndex: Int = 0
        var pathIndex = 0
        var isNumber = true
        var numberSign = 1
        var arrayIndexes: [Int?] = []
        let splitByte: UInt8 = pathSplitter.utf8.first.unsafelyUnwrapped
        var repetitionCombo = 1
        var searchDepths: [Int] = []
        var assignedDepth = 1
        
        if path.isEmpty {
            return (paths, lightMatch, arrayIndexes, searchDepths)
        }
        
        let pathBytes = Array(path.utf8)
        for char in pathBytes {
            if char == splitByte {
                if !word.isEmpty {
                    let depth = getIntermediateSymbolDepthLimit(word)
                    if let depth {
                        assignedDepth = depth
                    } else {
                        arrayIndexes.append(isNumber ? arrayIndex * numberSign : nil)
                        lightMatch.append(repetitionCombo)
                        paths.append(word)
                        searchDepths.append(assignedDepth)
                        assignedDepth = 1
                    }
                    pathIndex += 1
                    word = []
                    isNumber = true
                    numberSign = 1
                    arrayIndex = 0
                    repetitionCombo = 0
                }
                repetitionCombo += 1
            } else {
                if repetitionCombo == 1 {
                    if (char > 47 && char < 58) {
                        if isNumber {
                            arrayIndex = (arrayIndex * 10) + (Int(char) - 48)
                        }
                    } else if isNumber && char == 45 {
                        numberSign = numberSign == 1 ? -1 : 1
                    } else {
                        isNumber = false
                    }
                    word.append(char)
                } else {
                    isNumber = false
                    if (char > 96 && char < 123) || (char > 47 && char < 58) {
                        word.append(char)
                    }  else if char > 64 && char < 91 {
                        word.append(char + 32)
                    }
                }
            }
        }
        arrayIndexes.append(isNumber ? arrayIndex * numberSign : nil)
        lightMatch.append(repetitionCombo)
        paths.append(word)
        let lastDepth = getIntermediateSymbolDepthLimit(word)
        if lastDepth == nil {
            searchDepths.append(assignedDepth)
        } else {
            paths.append(intermediateSymbol)
        }
        
        if pathSplitter != "." {
            pathSplitter = "."
        }

        return (paths, lightMatch, arrayIndexes, searchDepths)
    }
    
    private func asString(_ bytes: [UInt8]) -> String {
        return String(bytes.map({Character(UnicodeScalar($0))}))
    }
    
    private func trimSpace(_ input: String) -> String {
        var output = input
        while(output.last!.isWhitespace) {
            output.removeLast()
        }
        return output
    }
}
