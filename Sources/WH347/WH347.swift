// WH347 computes one line and one week of the U.S. Department of Labor
// WH-347 certified payroll form, revised version (Rev. January 2025), used on
// Davis-Bacon and Related Acts contracts.
//
// Given a worker's week (base rate, fringe rates per plan, straight-time and
// overtime hours per day, cash in lieu of fringe, deductions), `computeLine(_:)`
// returns columns 5 to 9 of the form and `computeRun(_:)` adds the per-plan
// fringe totals for the crew and a reconciliation check of column 6B. The
// package has no dependencies and no I/O.
//
// Arithmetic is plain `Double` with no intermediate rounding; `roundCents(_:)`
// rounds to the cent (halves toward +Inf) and is meant for display only. The
// ST/OT split is entered by the user, not computed from a daily or weekly
// threshold.
//
// Not an official DOL tool, not legal advice; you remain responsible for your
// certified payrolls. The package does not check wage determinations, fill the
// Statement of Compliance (page 2), or produce the form itself.
//
// DOL instructions for the WH-347: https://www.dol.gov/agencies/whd/forms/wh347
//
// The same calculations are available as a hosted tool at
// https://tabletemplates.com/certified-payroll-software/.
//
// Swift port of the Go package codeberg.org/tresor2k/tabletemplates-go/wh347,
// itself a port of the Rust crate wh347.

/// Tolerance for cent-level comparisons (7B vs 7A check, 6B reconciliation).
public let reconciliationTolerance: Double = 0.005

/// Overtime multiplier applied to the base rate (column 6A, OT line).
public let otMultiplier: Double = 1.5

/// Sanity threshold: more weekly hours than this is flagged `Sanity.review`.
public let maxSaneWeekHours: Double = 112.0

/// Fringe benefit rates in $/hour, one per plan.
public struct FringeRates: Sendable, Equatable, Codable {
    /// Health and welfare plan, $/h.
    public var healthWelfare: Double
    /// Pension plan, $/h.
    public var pension: Double
    /// Vacation / holiday plan, $/h.
    public var vacation: Double
    /// Training plan, $/h.
    public var training: Double

    /// Creates fringe rates; every plan defaults to zero.
    public init(healthWelfare: Double = 0, pension: Double = 0, vacation: Double = 0, training: Double = 0) {
        self.healthWelfare = healthWelfare
        self.pension = pension
        self.vacation = vacation
        self.training = training
    }

    /// The total hourly fringe credit: the sum of the 4 plan rates.
    public var total: Double {
        healthWelfare + pension + vacation + training
    }
}

/// Itemized weekly deductions in $ for all work (column 8).
/// They are entered, never computed.
public struct Deductions: Sendable, Equatable, Codable {
    /// FICA withholding.
    public var fica: Double
    /// Federal income tax withholding.
    public var federalTax: Double
    /// State income tax withholding.
    public var stateTax: Double
    /// Other permissible deductions.
    public var other: Double

    /// Creates deductions; every item defaults to zero.
    public init(fica: Double = 0, federalTax: Double = 0, stateTax: Double = 0, other: Double = 0) {
        self.fica = fica
        self.federalTax = federalTax
        self.stateTax = stateTax
        self.other = other
    }

    /// The column 8 total: the sum of the 4 itemized deductions.
    public var total: Double {
        fica + federalTax + stateTax + other
    }
}

/// Column 2 of the revised form. `.unset` means not entered
/// (printed blank, never defaulted to "J").
public enum WorkerType: Int, Sendable, Equatable, Codable, CustomStringConvertible {
    /// Not entered.
    case unset = 0
    /// "J" — journeyworker.
    case journeyworker = 1
    /// "RA" — registered apprentice.
    case registeredApprentice = 2

    /// The form code: "J", "RA", or "" when not entered.
    public var description: String {
        switch self {
        case .journeyworker:
            return "J"
        case .registeredApprentice:
            return "RA"
        case .unset:
            return ""
        }
    }
}

/// One worker's week on one project: the input of one WH-347 line.
public struct WorkerWeek: Sendable, Equatable, Codable {
    /// Hourly base rate actually paid, $/h (column 6A, ST line).
    public var baseRate: Double
    /// Hourly fringe credit per plan (column 6B is derived from it).
    public var fringe: FringeRates
    /// Straight-time hours per day, 7 days of the payroll week.
    public var stByDay: [Double]
    /// Overtime hours per day, 7 days of the payroll week.
    /// The ST/OT split is entered, not computed.
    public var otByDay: [Double]
    /// Itemized deductions for all work (column 8).
    public var deductions: Deductions
    /// Cash paid in lieu of fringe benefits, $/h (column 6C). Zero means none.
    public var cashInLieuRate: Double
    /// Gross earned for all work, all projects (column 7B). `nil` means 7B = 7A.
    public var grossAllWork: Double?
    /// Column 2. `.unset` means not entered.
    public var workerType: WorkerType

    /// Creates a worker week; every field defaults to zero / not entered,
    /// and the daily hours default to 7 zero entries.
    public init(
        baseRate: Double = 0,
        fringe: FringeRates = FringeRates(),
        stByDay: [Double] = [0, 0, 0, 0, 0, 0, 0],
        otByDay: [Double] = [0, 0, 0, 0, 0, 0, 0],
        deductions: Deductions = Deductions(),
        cashInLieuRate: Double = 0,
        grossAllWork: Double? = nil,
        workerType: WorkerType = .unset
    ) {
        self.baseRate = baseRate
        self.fringe = fringe
        self.stByDay = stByDay
        self.otByDay = otByDay
        self.deductions = deductions
        self.cashInLieuRate = cashInLieuRate
        self.grossAllWork = grossAllWork
        self.workerType = workerType
    }
}

/// Result of the per-line sanity check.
public enum Sanity: Int, Sendable, Equatable, Codable, CustomStringConvertible {
    /// No anomaly detected.
    case ok = 0
    /// Net pay < 0, hours > 112, base rate < 0, or entered 7B < 7A.
    case review = 1

    /// "ok" or "review".
    public var description: String {
        self == .review ? "review" : "ok"
    }
}

/// One computed WH-347 line (Rev. January 2025 columns 2 and 5-9).
public struct Line: Sendable, Equatable, Codable {
    /// Column 2 — copied from the input.
    public let workerType: WorkerType
    /// Column 5 — straight-time hours for the week.
    public let stHours: Double
    /// Column 5 — overtime hours for the week.
    public let otHours: Double
    /// Column 5 — total hours (ST + OT).
    public let totalHours: Double
    /// Column 6A, ST line — base rate, $/h.
    public let stRate: Double
    /// Column 6A, OT line — base rate × 1.5, $/h.
    public let otRate: Double
    /// Wages ST × rate + OT × rate × 1.5 (excludes 6C).
    public let gross: Double
    /// Column 6B — total hours × total fringe $/h.
    public let fringeCredit: Double
    /// Column 6C — total hours × cash-in-lieu $/h.
    public let cashInLieu: Double
    /// Column 7A — gross earned on this project: wages + 6C.
    public let grossProject: Double
    /// Column 7B — gross earned for all work: entered value, else 7A.
    public let grossAllWork: Double
    /// True when 7B was entered, false when it defaulted to 7A.
    public let grossAllWorkEntered: Bool
    /// Column 8 — total deductions for all work.
    public let totalDeductions: Double
    /// Column 9 — 7B − 8. The 6B fringe credit is never included.
    public let netPay: Double
    /// Base rate + total fringe, $/h (utility value, not a form column).
    public let ratePlusFringe: Double
    /// Sanity flag.
    public let sanity: Sanity
}

/// A computed run: one project, one week.
public struct Run: Sendable, Equatable, Codable {
    /// One line per input worker, in input order.
    public let lines: [Line]
    /// Crew totals paid to each plan: Σ total hours × plan rate.
    public let planTotals: FringeRates
    /// Sum of the 4 plan totals.
    public let planTotalsSum: Double
    /// Sum of column 6B over all lines.
    public let fringeColumnSum: Double
    /// |fringeColumnSum − planTotalsSum| < 0.005.
    public let reconciles: Bool
}

private func sumWeek(_ days: [Double]) -> Double {
    var s = 0.0
    for d in days {
        s += d
    }
    return s
}

/// Computes one WH-347 line. No intermediate rounding: use `roundCents(_:)`
/// for display only.
///
/// The operations are performed in the same order as the Go package and the
/// Rust crate (Swift does not fuse multiply-add by default), so results are
/// bit-identical.
public func computeLine(_ w: WorkerWeek) -> Line {
    let st = sumWeek(w.stByDay)
    let ot = sumWeek(w.otByDay)
    let hours = st + ot
    let fringeRate = w.fringe.total
    let otRate = w.baseRate * otMultiplier
    let gross = (st * w.baseRate) + ((ot * w.baseRate) * otMultiplier)
    let cashInLieu = hours * w.cashInLieuRate
    let grossProject = gross + cashInLieu
    let grossAllWork = w.grossAllWork ?? grossProject
    let deductions = w.deductions.total
    let net = grossAllWork - deductions
    var sanity = Sanity.ok
    if net < 0 || hours > maxSaneWeekHours || w.baseRate < 0
        || grossAllWork < grossProject - reconciliationTolerance {
        sanity = .review
    }
    return Line(
        workerType: w.workerType,
        stHours: st,
        otHours: ot,
        totalHours: hours,
        stRate: w.baseRate,
        otRate: otRate,
        gross: gross,
        fringeCredit: hours * fringeRate,
        cashInLieu: cashInLieu,
        grossProject: grossProject,
        grossAllWork: grossAllWork,
        grossAllWorkEntered: w.grossAllWork != nil,
        totalDeductions: deductions,
        netPay: net,
        ratePlusFringe: w.baseRate + fringeRate,
        sanity: sanity
    )
}

/// Computes a full run: all lines, per-plan fringe totals and the 6B
/// reconciliation.
public func computeRun(_ workers: [WorkerWeek]) -> Run {
    var lines: [Line] = []
    lines.reserveCapacity(workers.count)
    var planTotals = FringeRates()
    var fringeColumnSum = 0.0
    for w in workers {
        let l = computeLine(w)
        lines.append(l)
        let h = l.totalHours
        planTotals.healthWelfare += h * w.fringe.healthWelfare
        planTotals.pension += h * w.fringe.pension
        planTotals.vacation += h * w.fringe.vacation
        planTotals.training += h * w.fringe.training
        fringeColumnSum += l.fringeCredit
    }
    let planTotalsSum = planTotals.total
    return Run(
        lines: lines,
        planTotals: planTotals,
        planTotalsSum: planTotalsSum,
        fringeColumnSum: fringeColumnSum,
        reconciles: abs(fringeColumnSum - planTotalsSum) < reconciliationTolerance
    )
}

/// Rounds to cents, halves toward +Inf (same as JavaScript
/// `Math.round(n * 100) / 100`). For display and snapshots only, never inside
/// the calculation.
public func roundCents(_ n: Double) -> Double {
    let x = n * 100
    var f = x.rounded(.down)
    if x - f >= 0.5 {
        f += 1
    }
    return f / 100
}
