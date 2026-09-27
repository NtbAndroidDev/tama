import Foundation
import Testing
@testable import Droppy

@Suite struct MathEvaluatorTests {
    private func eval(_ s: String) -> Double? { MathEvaluator.evaluate(s) }

    @Test(arguments: [
        ("2+3*4", 14.0), ("(2+3)*4", 20), ("10-4-3", 3), ("2^3^2", 512), ("7/2", 3.5),
        ("10 % 4", 2), ("3 x 4", 12), ("6÷3", 2), ("2×3", 6), ("1,5+1", 2.5),
        ("  8 / 2 * 4 ", 16), ("2*-3", -6), ("--3", 3), ("+4", 4),
    ])
    func precedence(_ input: String, _ expected: Double) {
        #expect(eval(input) == expected)
    }

    @Test func unicodeMinusSign() {
        #expect(eval("5 \u{2212} 3") == 2)
        #expect(eval("\u{2212}2^2") == -4)
    }

    @Test(arguments: [
        ("1,000 * 2", 2000.0), ("1,000,000", 1_000_000), ("12,345.5", 12345.5),
        ("1,5", 1.5), ("1,50", 1.5), (",5", 0.5), ("2,5*2", 5),
    ])
    func commas(_ input: String, _ expected: Double) {
        #expect(eval(input) == expected)
    }

    @Test(arguments: ["1,2,3", "1.5,2", "1,0000,000"])
    func invalidCommas(_ input: String) {
        #expect(eval(input) == nil)
    }

    @Test func unaryMinusBindsLooserThanPower() {
        #expect(eval("-2^2") == -4)
        #expect(eval("(-2)^2") == 4)
        #expect(eval("2^-1") == 0.5)
        #expect(eval("-3*-3") == 9)
    }

    @Test func functionsAndConstants() throws {
        #expect(eval("sqrt(16)") == 4)
        #expect(eval("abs(-5)") == 5)
        #expect(try #require(eval("log(1000)")).isApproximately(3))
        #expect(try #require(eval("ln(e)")).isApproximately(1))
        #expect(eval("round(2.5)") == 3)
        #expect(eval("floor(-1.5)") == -2)
        #expect(eval("ceil(1.2)") == 2)
        #expect(try #require(eval("sin(pi/2)")).isApproximately(1))
        #expect(try #require(eval("cos(0)")).isApproximately(1))
        #expect(eval("π") == .pi)
        #expect(eval("PI") == .pi)
        #expect(eval("2*sqrt(9)+1") == 7)
    }

    @Test(arguments: ["1/0", "5%0", "0/0", "sqrt(-1)", "log(0)", "ln(-2)", "2+", "(1+2", "1+2)",
                      "foo(1)", "", "   ", "1.2.3", "2π", "abc", "sqrt 4", "2xpi"])
    func invalidInputReturnsNil(_ input: String) {
        #expect(eval(input) == nil)
    }

    @Test func overflowIsRejected() {
        #expect(eval("10^400") == nil)
    }

    @Test func formatting() {
        #expect(MathEvaluator.format(3) == "3")
        #expect(MathEvaluator.format(-0.0) == "0")
        #expect(MathEvaluator.format(0.1 + 0.2) == "0.3")
        #expect(MathEvaluator.format(1.0 / 3) == "0.333333")
        #expect(MathEvaluator.format(-2.5) == "-2.5")
        #expect(MathEvaluator.format(1e15) == "1000000000000000")
    }
}

extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 1e-9) -> Bool { abs(self - other) <= tolerance }
}
