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
    
    func expect(_ test: Bool, _ index: Int) {
        if test {
            print("command \(index + 1) has successfully passed")
        } else {
            print("command \(index + 1) has failed")
        }
    }
    func commandSeries(_ commands: [String], instance: JSONEntity) throws {
        for (index, command) in commands.enumerated() {
            let segments1 = command.components(separatedBy: " = ")
            let segments2 = segments1[0].components(separatedBy: " as ")
            let path = segments2[0]
            let expectedValue = segments1.count == 2 ? segments1[1] : nil
            let type = segments2.count == 2 ? "dump" : segments2[1]
            switch(type) {
                case "string":
                    expect(instance.string(path) == expectedValue, index)
                case "number":
                    expect(instance.number(path) == Double(expectedValue!), index)
                case "bool":
                    expect(instance.bool(path) == (expectedValue == "nil" ? nil : (expectedValue == "true")), index)
                case "null":
                    expect(instance.isNull(path) == (expectedValue == "true"), index)
                case "object":
                    print(instance.object(path)?.export() ?? "expected object is null")
                case "array":
                    print(instance.object(path)?.export() ?? "expected array is null")
                default:
                    if expectedValue != nil {
                        expect(instance.convertToString(path) == expectedValue, index)
                    } else {
                        print("command \(index + 1) results - \(instance.convertToString(path) ?? "nothing")")
                    }
            }
        }
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
            let entity = JSONEntity(jsonData.withUnsafeBytes)
//            try commandSeries([
//                "???.ahago as string = hello",
//                "???.moredetails.temperature as number = 87",
//                "???.1.???.place as string = Galle",
//            ], instance: entity)
            print("results", (entity.object("???.moredetails")?.value()?.value as! JSONEntity).export() ?? "nothing")
//            print(id ?? "nothing")
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
