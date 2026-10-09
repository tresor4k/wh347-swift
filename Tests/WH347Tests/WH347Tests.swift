// Parity with the Go package wh347 (wh347_test.go), itself in parity with the
// Rust crate wh347 0.1.0 (tests/engine.rs). Every case and expected value is
// copied from wh347_test.go; tools/crosscheck.mjs verifies it one by one.
import XCTest
import WH347

private func johnMason() -> WorkerWeek {
    WorkerWeek(
        baseRate: 30,
        fringe: FringeRates(healthWelfare: 4, pension: 2),
        stByDay: [8, 8, 8, 8, 8, 0, 0],
        otByDay: [4, 0, 0, 0, 0, 0, 0],
        deductions: Deductions(other: 310)
    )
}

private func worker() -> WorkerWeek {
    WorkerWeek(
        baseRate: 20,
        fringe: FringeRates(healthWelfare: 1, pension: 1, vacation: 0.5, training: 0.25),
        stByDay: [8, 8, 8, 8, 8, 0, 0]
    )
}

private func with(_ w: WorkerWeek, _ f: (inout WorkerWeek) -> Void) -> WorkerWeek {
    var w = w
    f(&w)
    return w
}

final class WH347Tests: XCTestCase {
    private var currentCase = ""

    /// Same check as the Go helper `near` (vitest toBeCloseTo(expected, 2)): |a − e| < 0.005.
    private func near(_ field: String, _ actual: Double, _ expected: Double,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(abs(actual - expected), 0.005,
                          "\(currentCase): \(field): expected \(expected), got \(actual)",
                          file: file, line: line)
    }

    private func eq<T: Equatable>(_ field: String, _ actual: T, _ expected: T,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual, expected, "\(currentCase): \(field)", file: file, line: line)
    }

    private func checkLine(_ name: String, _ input: WorkerWeek, _ body: (Line) -> Void) {
        currentCase = name
        body(computeLine(input))
    }

    private func checkRun(_ name: String, _ input: [WorkerWeek], _ body: (Run) -> Void) {
        currentCase = name
        body(computeRun(input))
    }

    private func checkTotal(_ name: String, _ input: FringeRates, _ want: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
        currentCase = name
        eq("Total", input.total, want, file: file, line: line)
    }

    private func checkRound(_ input: Double, _ want: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
        currentCase = "\(input)"
        eq("RoundCents", roundCents(input), want, file: file, line: line)
    }

    func testComputeLine() {
        // --- parity.test.ts ---
        checkLine("SC-WH-1 gross ST+OT", johnMason()) { l in
            near("STHours", l.stHours, 40)
            near("OTHours", l.otHours, 4)
            near("Gross", l.gross, 1380)
        }
        checkLine("SC-WH-3 net is cash pay", johnMason()) { l in
            near("NetPay", l.netPay, 1070)
        }
        // --- edge-cases.test.ts ---
        checkLine("zero hours", with(worker()) { w in w.stByDay = [0, 0, 0, 0, 0, 0, 0] }) { l in
            eq("Gross", l.gross, 0)
            eq("FringeCredit", l.fringeCredit, 0)
            eq("NetPay", l.netPay, 0)
            eq("Sanity", l.sanity, Sanity.ok)
        }
        checkLine("overtime only", with(worker()) { w in
            w.stByDay = [0, 0, 0, 0, 0, 0, 0]
            w.otByDay = [0, 0, 0, 0, 0, 6, 4]
        }) { l in
            eq("STHours", l.stHours, 0)
            eq("OTHours", l.otHours, 10)
            near("Gross", l.gross, 300)
            near("FringeCredit", l.fringeCredit, 27.5)
        }
        checkLine("negative net is review", with(worker()) { w in w.deductions = Deductions(federalTax: 2000) }) { l in
            near("Gross", l.gross, 800)
            near("NetPay", l.netPay, -1200)
            eq("Sanity", l.sanity, Sanity.review)
        }
        checkLine("itemized deductions sum", with(worker()) { w in
            w.deductions = Deductions(fica: 61.2, federalTax: 90, stateTax: 38.5, other: 10.3)
        }) { l in
            near("TotalDeductions", l.totalDeductions, 200)
            near("NetPay", l.netPay, 600)
        }
        checkLine("hours threshold 112 ok", with(worker()) { w in
            w.stByDay = [16, 16, 16, 16, 16, 16, 16]
        }) { l in
            eq("STHours", l.stHours, 112)
            eq("Sanity", l.sanity, Sanity.ok)
        }
        checkLine("hours threshold 112 over", with(worker()) { w in
            w.stByDay = [16, 16, 16, 16, 16, 16, 16]
            w.otByDay = [0.25, 0, 0, 0, 0, 0, 0]
        }) { l in
            eq("Sanity", l.sanity, Sanity.review)
        }
        checkLine("negative rate is review", with(worker()) { w in
            w.baseRate = -1
            w.stByDay = [1, 0, 0, 0, 0, 0, 0]
        }) { l in
            eq("Sanity", l.sanity, Sanity.review)
        }
        checkLine("rate plus fringe", worker()) { l in
            near("RatePlusFringe", l.ratePlusFringe, 22.75)
        }
        checkLine("rev2025 defaults neutral", worker()) { l in
            eq("CashInLieu", l.cashInLieu, 0)
            eq("GrossProject", l.grossProject, l.gross)
            eq("GrossAllWork", l.grossAllWork, l.grossProject)
            eq("GrossAllWorkEntered", l.grossAllWorkEntered, false)
            near("NetPay", l.netPay, 800)
            eq("WorkerType", l.workerType, WorkerType.unset)
            near("OTRate", l.otRate, 30)
        }
        checkLine("col 6C cash in lieu", with(worker()) { w in
            w.cashInLieuRate = 2
            w.otByDay = [2, 0, 0, 0, 0, 0, 0]
        }) { l in
            near("CashInLieu", l.cashInLieu, 84)
            near("GrossProject", l.grossProject, 944)
            near("GrossAllWork", l.grossAllWork, 944)
            near("FringeCredit", l.fringeCredit, 42*2.75)
            near("NetPay", l.netPay, 944)
            eq("Sanity", l.sanity, Sanity.ok)
        }
        checkLine("col 7B entered more", with(worker()) { w in
            w.grossAllWork = 1500
            w.deductions = Deductions(federalTax: 200)
        }) { l in
            eq("GrossAllWorkEntered", l.grossAllWorkEntered, true)
            eq("GrossAllWork", l.grossAllWork, 1500)
            near("NetPay", l.netPay, 1300)
            eq("Sanity", l.sanity, Sanity.ok)
        }
        checkLine("col 7B entered less", with(worker()) { w in w.grossAllWork = 700 }) { l in
            eq("Sanity", l.sanity, Sanity.review)
        }
        checkLine("col 7B entered zero", with(worker()) { w in
            w.stByDay = [0, 0, 0, 0, 0, 0, 0]
            w.grossAllWork = 0
        }) { l in
            eq("GrossAllWorkEntered", l.grossAllWorkEntered, true)
            eq("Sanity", l.sanity, Sanity.ok)
        }
        checkLine("col 2 registered apprentice", with(worker()) { w in w.workerType = .registeredApprentice }) { l in
            eq("WorkerType", l.workerType, WorkerType.registeredApprentice)
        }
        checkLine("col 2 journeyworker", with(worker()) { w in w.workerType = .journeyworker }) { l in
            eq("WorkerType", l.workerType, WorkerType.journeyworker)
        }
    }

    func testComputeRun() {
        checkRun("SC-WH-2 fringe 6B reconciles", [johnMason()]) { r in
            near("FringeCredit", r.lines[0].fringeCredit, 264)
            eq("Sanity", r.lines[0].sanity, Sanity.ok)
            near("PlanTotals.HealthWelfare", r.planTotals.healthWelfare, 176)
            near("PlanTotalsSum", r.planTotalsSum, 264)
            near("FringeColumnSum", r.fringeColumnSum, 264)
            eq("Reconciles", r.reconciles, true)
        }
        checkRun("empty crew", []) { r in
            eq("len(Lines)", r.lines.count, 0)
            eq("FringeColumnSum", r.fringeColumnSum, 0)
            eq("PlanTotalsSum", r.planTotalsSum, 0)
            eq("Reconciles", r.reconciles, true)
        }
        checkRun("zero fringe reconciles", [with(worker()) { w in w.fringe = FringeRates() }]) { r in
            eq("FringeCredit", r.lines[0].fringeCredit, 0)
            eq("PlanTotalsSum", r.planTotalsSum, 0)
            eq("Reconciles", r.reconciles, true)
        }
        checkRun("multi worker reconciliation", [
            worker(),
            with(worker()) { w in w.fringe = FringeRates(pension: 3.33, vacation: 1.11) },
            with(worker()) { w in
                w.fringe = FringeRates()
                w.otByDay = [2, 2, 2, 2, 2, 0, 0]
            },
        ]) { r in
            eq("Reconciles", r.reconciles, true)
            near("FringeColumnSum", r.fringeColumnSum, r.planTotalsSum)
        }
    }

    func testFringeRatesTotal() {
        checkTotal("derived", FringeRates(healthWelfare: 4, pension: 2), 6)
        checkTotal("zero", FringeRates(), 0)
    }

    func testRoundCents() {
        checkRound(1069.999999999, 1070)
        checkRound(0.005, 0.01)
        checkRound(-1.005, -1)
        checkRound(-0.125, -0.12) // half toward +Inf, like JS Math.round
        checkRound(2.675, 2.68) // same as node: Math.round(2.675 * 100) / 100
    }

    func testExampleComputeLine() {
        currentCase = "ExampleComputeLine"
        let week = WorkerWeek(
            baseRate: 30,
            fringe: FringeRates(healthWelfare: 4, pension: 2),
            stByDay: [8, 8, 8, 8, 8, 0, 0],
            otByDay: [4, 0, 0, 0, 0, 0, 0],
            deductions: Deductions(other: 310)
        )
        let l = computeLine(week)
        eq("Output", l.totalHours, 44)
        eq("Output", l.otRate, 45)
        eq("Output", roundCents(l.fringeCredit), 264)
        eq("Output", roundCents(l.grossProject), 1380)
        eq("Output", roundCents(l.netPay), 1070)
        eq("Output", l.sanity.description, "ok")

        let r = computeRun([week])
        eq("Output", roundCents(r.planTotals.healthWelfare), 176)
        eq("Output", r.reconciles, true)
    }
}
