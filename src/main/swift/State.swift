//
//  File.swift
//  
//
//  Created by Nishain De Silva on 2023-06-11.
//

internal class State {
    internal var jsonText: String = ""
    internal var jsonData: UnsafeRawBufferPointer = UnsafeRawBufferPointer.init(start: nil, count: 0)
    internal var jsonDataMemoryHolder: [UInt8] = []
    internal var contentType: String = "string"
    internal var extractInnerContent = false
    internal var intermediateSymbol: [UInt8] = [63, 63, 63]
    internal var errorHandler: ((ErrorInfo) -> Void)? = nil
    internal var errorInfo: (code: ErrorCode, occurredQueryIndex: Int)? = nil
    internal var pathSplitter: Character = "."
    internal var isBubbling: Bool = false
    internal var quotation: UInt8 = 34
}
