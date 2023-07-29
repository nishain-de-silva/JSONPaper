//
//  File.swift
//  
//
//  Created by Nishain De Silva on 2023-07-14.
//
@usableFromInline
internal struct PeekIterator {
    @usableFromInline
    var base: UnsafeRawPointer
    @usableFromInline
    let end: UnsafeRawPointer
    
    @usableFromInline
    let TYPE = UInt8.self

    
    internal init(_ pointer: UnsafeRawBufferPointer) {
        base = pointer.baseAddress!
        end = base + pointer.count
    }
    
        
    @inlinable
    mutating func next() -> UInt8 {
        let value = base.load(as: TYPE)
        base += 1
        return value
    }
    
    @inlinable
    func hasNext() -> Bool {
        return base < end
    }
    
    @inlinable
    mutating func moveBack() {
        base -= 1
    }
}
