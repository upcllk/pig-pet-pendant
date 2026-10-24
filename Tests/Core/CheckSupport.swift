import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    if !condition() { throw CheckFailure(description: "\(file):\(line): condition was false") }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                               file: StaticString = #filePath, line: UInt = #line) throws {
    if actual != expected {
        throw CheckFailure(description: "\(file):\(line): expected \(expected), got \(actual)")
    }
}

func expectEqual(_ actual: Double, _ expected: Double, accuracy: Double,
                 file: StaticString = #filePath, line: UInt = #line) throws {
    try expect(abs(actual - expected) <= accuracy, file: file, line: line)
}

func expectNotEqual<T: Equatable>(_ actual: T, _ other: T,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
    try expect(actual != other, file: file, line: line)
}

func expectGreaterThan<T: Comparable>(_ actual: T, _ other: T,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
    try expect(actual > other, file: file, line: line)
}

func expectLessThan<T: Comparable>(_ actual: T, _ other: T,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
    try expect(actual < other, file: file, line: line)
}

func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws {
    try expect(value == nil, file: file, line: line)
}

func requireValue<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value = value else { throw CheckFailure(description: "\(file):\(line): unexpected nil") }
    return value
}

func expectThrows<T>(_ expression: @autoclosure () throws -> T,
                     file: StaticString = #filePath, line: UInt = #line) throws {
    do {
        _ = try expression()
    } catch {
        return
    }
    throw CheckFailure(description: "\(file):\(line): expected an error")
}
