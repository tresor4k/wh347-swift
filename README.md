# WH347 (Swift)

Swift port of the Go package
[`codeberg.org/tresor2k/tabletemplates-go/wh347`](https://pkg.go.dev/codeberg.org/tresor2k/tabletemplates-go/wh347),
itself a port of the Rust crate [`wh347`](https://crates.io/crates/wh347).
The test suite replays every case of the Go tests with the same expected values.

Calculations for one line and one week of the U.S. Department of Labor
**WH-347 certified payroll form, revised version (Rev. January 2025)**, used on
Davis-Bacon and Related Acts contracts.

The previous version of the form carries an OMB expiration date of 09/30/2026.

Given a worker's week (base rate, fringe rates per plan, straight-time and overtime
hours per day, cash in lieu of fringe, deductions), the package computes columns 5
to 9 of the form, per-plan fringe totals for the crew, and a reconciliation check.
It has no dependencies (not even Foundation) and no I/O.

- Step-by-step guide to the form: <https://tabletemplates.com/how-to-fill-out-wh-347/>
- Hosted tool that produces the WH-347 from the same calculations (LeaveSheet):
  <https://tabletemplates.com/certified-payroll-software/>

## Install

Swift Package Manager, in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tresor4k/wh347-swift.git", from: "0.1.0")
],
targets: [
    .target(name: "YourTarget", dependencies: [
        .product(name: "WH347", package: "wh347-swift")
    ])
]
```

## Example

```swift
import WH347

let week = WorkerWeek(
    baseRate: 30,
    fringe: FringeRates(healthWelfare: 4, pension: 2),
    stByDay: [8, 8, 8, 8, 8, 0, 0],
    otByDay: [4, 0, 0, 0, 0, 0, 0],
    deductions: Deductions(other: 310)
)

let line = computeLine(week)
print(line.totalHours)               // 44.0   column 5
print(line.otRate)                   // 45.0   column 6A, OT line
print(roundCents(line.fringeCredit)) // 264.0  column 6B
print(roundCents(line.grossProject)) // 1380.0 column 7A
print(roundCents(line.netPay))       // 1070.0 column 9
print(line.sanity)                   // ok

let run = computeRun([week])
print(roundCents(run.planTotals.healthWelfare)) // 176.0
print(run.reconciles)                           // true
```

## Columns of the revised form

| Column | Content | In this package |
|---|---|---|
| 1A | Worker entry number | not handled (identity) |
| 1B / 1C / 1D | Last name / first name / middle initial | not handled (identity) |
| 1E | Worker identifying number (e.g. last 4 digits of the SSN) | not handled (identity) |
| 2 | "J" journeyworker or "RA" registered apprentice | `WorkerWeek.workerType`, copied to `Line.workerType` |
| 3 | Labor classification | not handled |
| 4 | Hours worked each day, ST and OT lines | `WorkerWeek.stByDay`, `WorkerWeek.otByDay` |
| 5 | Total hours for the week | `Line.stHours`, `Line.otHours`, `Line.totalHours` |
| 6A | Hourly rate paid, ST and OT lines (excluding cash in lieu of fringe) | `Line.stRate`, `Line.otRate` = base rate × 1.5 |
| 6B | Total fringe benefit credit | `Line.fringeCredit` = total hours × total hourly fringe credit |
| 6C | Payment in lieu of fringe benefits | `Line.cashInLieu` = total hours × `cashInLieuRate` |
| 7A | Gross amount earned, this project | `Line.grossProject` = ST × rate + OT × rate × 1.5 + 6C |
| 7B | Gross amount earned, all work | `Line.grossAllWork` = entered value (`WorkerWeek.grossAllWork` non-nil), else 7A |
| 8 | Deductions for all work | `Line.totalDeductions` = sum of the itemized deductions |
| 9 | Net payment for all work | `Line.netPay` = 7B − 8 (the 6B fringe credit is never included) |

`Line.sanity` is `.review` when the net pay is negative, the week exceeds 112 hours,
the base rate is negative, or an entered 7B is lower than 7A.

Arithmetic is plain `Double` with no intermediate rounding; `roundCents(_:)` rounds to the
cent (halves toward +∞, like the Go `RoundCents`) and is meant for display only. The ST/OT
split is entered by the user, not computed from a daily or weekly threshold.

All public types are `Sendable`, `Equatable` and `Codable`.

## Parity with the Go package

`tools/crosscheck.mjs` (Node, no dependencies) compares `Tests/WH347Tests/WH347Tests.swift`
with the Go `wh347_test.go`: case names, input values and expected values, one by one.

```sh
node tools/crosscheck.mjs path/to/wh347_test.go
swift test
```

## Scope and disclaimer

Not an official DOL tool, not legal advice; you remain responsible for your certified payrolls.
The package does not check wage determinations, fill the Statement of Compliance
(page 2), or produce the form itself.

- DOL instructions for the WH-347: <https://www.dol.gov/agencies/whd/forms/wh347>
- Guide: <https://tabletemplates.com/how-to-fill-out-wh-347/>
- The same calculations are available as a hosted tool at
  <https://tabletemplates.com/certified-payroll-software/>.

## License

MIT, see [LICENSE](LICENSE). Published by TableTemplates.
