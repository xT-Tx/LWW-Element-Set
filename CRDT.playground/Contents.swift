import Foundation
import XCTest

protocol AnyValue {
    func transform() -> Data
}

extension String: AnyValue {
    func transform() -> Data {
        return self.data(using: .utf8)!
    }
}

extension UIImage: AnyValue {
    func transform() -> Data {
        return self.pngData()!
    }
}
// could have more extensions...

struct Element {
    static func == (lhs: Element, rhs: Element) -> Bool {
        return lhs.payload == rhs.payload
    }
    
    fileprivate var payload: Data
    fileprivate var timestamp: TimeInterval
    
    init(rawValue: AnyValue, timestamp: TimeInterval = 0.0) {
        if let data = rawValue as? Data {
            self.payload = data
        }
        else {
            self.payload = rawValue.transform()
        }
        self.timestamp = timestamp
    }
}


struct LWWSet {
    // I wanted to use something like `[Element<T>]()`. but swift does not support it.
    private var addSet = [Element]()
    private var removeSet = [Element]()
    fileprivate var mergedSet = [Element]()
    
    init() {
    }
    
    init(_ original: LWWSet) {
        mergedSet = original.mergedSet
    }
    
    mutating func add(_ value: AnyValue) {
        let e = Element(rawValue: value, timestamp: Date().timeIntervalSince1970)
        addSet.append(e)
    }
    
    mutating func remove(_ value: AnyValue) {
        let e = Element(rawValue: value, timestamp: Date().timeIntervalSince1970)
        removeSet.append(e)
    }
    
    mutating func merge(with source: LWWSet) {
        addSet.append(contentsOf: source.addSet)
        removeSet.append(contentsOf: source.removeSet)
        
        mergedSet.append(contentsOf: addSet)
        for element in removeSet {
            if let index = mergedSet.firstIndex(where: {$0 == element && $0.timestamp < element.timestamp}) {
                mergedSet.remove(at: index)
            }
        }
    }
    
    func lookup(_ value: AnyValue) -> Bool {
        let data = value.transform()
        return mergedSet.contains(where: { $0.payload == data })
    }
}

class UnitTests: XCTestCase {

    let emptySet = LWWSet()
    let image = UIImage(named: "ball")!
    
    func testAdd() {
        var replicaA = emptySet
        var replicaB = emptySet
        replicaA.add("Hello")
        replicaB.merge(with: replicaA)
        XCTAssertEqual(replicaB.mergedSet[0].payload, "Hello".transform())
        
        replicaB.add("world")
        replicaB.merge(with: replicaA)
        XCTAssertTrue(replicaB.lookup("world"))
        
        replicaA.add("there")
        replicaA.merge(with: replicaB)
        XCTAssertTrue(replicaA.lookup("world"))
        XCTAssertTrue(replicaA.lookup("there"))

        replicaA.add(image)
        replicaB.merge(with: replicaA)
        XCTAssertTrue(replicaB.lookup(image))
    }
    
    func testRemove() {
        var replicaA = emptySet
        var replicaB = emptySet
        replicaA.add("Hello")
        replicaA.add("world")
        replicaA.remove("Hello")
        replicaB.merge(with: replicaA)
        XCTAssertFalse(replicaB.lookup("Hello"))
        
        replicaA.merge(with: replicaA)
        XCTAssertFalse(replicaA.lookup("Hello"))
        
        replicaA.merge(with: replicaB)
        XCTAssertFalse(replicaA.lookup("Hello"))
        
        replicaB.add(image)
        replicaB.remove(image)
        XCTAssertFalse(replicaB.lookup(image))
    }
    
    func testConcurrentAddAndRemove() {
        var replicaA = emptySet
        var replicaB = emptySet
        replicaA.add("Hello")
        replicaB.remove("Hello")
        replicaA.merge(with: replicaB)
        XCTAssertFalse(replicaA.lookup("Hello"))
        
        replicaB.merge(with: replicaA)
        XCTAssertFalse(replicaB.lookup("Hello"))
        
        replicaB.remove("Hello")
        replicaA.add("Hello")
        replicaA.merge(with: replicaB)
        XCTAssertTrue(replicaA.lookup("Hello"))
        
        replicaB.merge(with: replicaA)
        XCTAssertTrue(replicaB.lookup("Hello"))
        
        replicaB.add(image)
        replicaA.remove(image)
        replicaB.merge(with: replicaA)
        XCTAssertFalse(replicaB.lookup(image))
    }
    
    func testRemoveNonexisting() {
        var replicaA = emptySet
        var replicaB = emptySet
        replicaB.remove("foo")
        replicaB.remove("bar")
        replicaA.add("Hello")
        replicaB.remove("there")
        replicaB.remove(image)
        replicaB.merge(with: replicaA)
        XCTAssertTrue(replicaB.lookup("Hello"))
        XCTAssertTrue(replicaB.mergedSet.count == 1)
    }
}



class TestObserver: NSObject, XCTestObservation {
    func testCase(_ testCase: XCTestCase,
                  didFailWithDescription description: String,
                  inFile filePath: String?,
                  atLine lineNumber: Int) {
        assertionFailure(description, line: UInt(lineNumber))
    }
}
XCTestObservationCenter.shared.addTestObserver(TestObserver())

UnitTests.defaultTestSuite.run()
