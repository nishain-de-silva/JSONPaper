//
//  JSONStoreTest.swift
//  
//
//  Created by Nishain De Silva on 2023-01-24.
//

import XCTest
import JSONStore

final class JSONStoreTest: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func executeRun() {
        let path = Bundle.module.path(forResource: "large-file", ofType: "json")
        do {
            let jsonData = try Data(contentsOf: URL(fileURLWithPath: path!))
//            var inputString = String(data: jsonData, encoding: .utf8)!
            let start = Date()
            let entity = JSONEntity()
            jsonData.withUnsafeBytes(entity.fetchBytes())
            let id = entity.justGet("11350.id")!
            print(id)
            print("elapsed time - ", Date().timeIntervalSince(start))
        } catch {
            print(error)
        }
    }
    
    
    func testExample() throws {
        
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results w;;ith assertions afterwards.
//        print("path - ", Bundle(for: JSONStoreTest.self).)
//        print("path)",  Bundle(for: JSONStoreTest.self).bundlePath )
        executeRun()
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            executeRun()
            // Put the code you want to measure the time of here.
        }
    }

}
