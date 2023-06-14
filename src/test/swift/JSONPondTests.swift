//
//  JSONPondTest.swift
//  
//
//  Created by Nishain De Silva on 2023-01-24.
//

import XCTest
import JSONPond

final class JSONPondTest: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testExample() throws {
        
        // This is an example of a functional test case.
        // Use XCTexpect and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results w;;ith expections afterwards.
        let path = Bundle.module.path(forResource: "test2", ofType: "json")
        do {
            let jsonData = try Data(contentsOf: URL(fileURLWithPath: path!))
            let start = Date()
            let pond = JSONBlock(jsonData.withUnsafeBytes)
            pond.onQueryFail(<#T##handler: (ErrorInfo) -> Void##(ErrorInfo) -> Void#>)
            let result = pond
                .onQueryFail({
                    print($0.explain())
                })
                .collection("..root.another")?.map({$0.string("bakerville")})
            
            print(result ?? "nothing")
            print("elapsed time - ", Date().timeIntervalSince(start))
        } catch {
            print(error)
        }
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            try! testExample()
            // Put the code you want to measure the time of here.
        }
    }

}
