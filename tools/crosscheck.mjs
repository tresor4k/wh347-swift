#!/usr/bin/env node
// Cross-checks the Swift tests against the Go reference tests, one value at a time.
// Usage: node tools/crosscheck.mjs [path/to/wh347_test.go]
// Default Go path: ../wh347-go/wh347_test.go (sibling package in the monorepo).
// Exit 0 only if every case name, input literal and expected value matches.
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const goPath = resolve(process.argv[2] ?? resolve(root, '..', 'wh347-go', 'wh347_test.go'));
const swiftPath = resolve(root, 'Tests', 'WH347Tests', 'WH347Tests.swift');
const go = readFileSync(goPath, 'utf8').replace(/\r\n/g, '\n');
const swift = readFileSync(swiftPath, 'utf8').replace(/\r\n/g, '\n');

const errors = [];
const fail = (msg) => errors.push(msg);

// --- helpers ---------------------------------------------------------------
const between = (src, start, end, label) => {
  const i = src.indexOf(start);
  if (i < 0) throw new Error(`${label}: start marker not found: ${start}`);
  const j = end === null ? src.length : src.indexOf(end, i + start.length);
  if (j < 0) throw new Error(`${label}: end marker not found: ${end}`);
  return src.slice(i + start.length, j);
};
const swiftFunc = (name) => {
  const body = between(swift, `func ${name}()`, null, name);
  const k = body.indexOf('\n    func ');
  return k < 0 ? body : body.slice(0, k);
};
const isAssert = (line) => /^\s*(near|eq)\(/.test(line);
const stripComments = (s) => s.replace(/\/\/[^\n]*/g, '');
const stripStrings = (s) => s.replace(/"[^"\n]*"/g, '""');
// Numeric literals of the non-assertion code (inputs), in order.
const literals = (code, lang) => {
  let s = stripStrings(stripComments(code))
    .split('\n').filter((l) => !isAssert(l)).join('\n');
  if (lang === 'go') {
    s = s.replace(/\[7\]float64\{\}/g, '{0, 0, 0, 0, 0, 0, 0}').replace(/\[7\]float64/g, '');
  }
  return [...s.matchAll(/(?<![\w.$])-?\d+(?:\.\d+)?/g)].map((m) => Number(m[0]));
};
const GO_CONST = {
  SanityOK: 'Sanity.ok',
  SanityReview: 'Sanity.review',
  WorkerTypeUnset: 'WorkerType.unset',
  Journeyworker: 'WorkerType.journeyworker',
  RegisteredApprentice: 'WorkerType.registeredApprentice',
};
const norm = (expr, lang) => {
  let e = expr.trim();
  if (lang === 'go') e = e.replace(/\b[A-Z]\w*\b/g, (w) => GO_CONST[w] ?? w);
  e = e.replace(/^"(.*)"$/, '$1').replace(/\s+/g, '').toLowerCase();
  return e !== '' && !Number.isNaN(Number(e)) ? String(Number(e)) : e;
};
// Assertions: [kind, field, normalized expected], in order.
const asserts = (code, lang) =>
  code.split('\n').filter(isAssert).map((raw) => {
    const l = raw.trim().replace(/\s*\/\/.*$/, '');
    const m = lang === 'go'
      ? l.match(/^(near|eq)\(t, "([^"]+)", (.*)\)$/)
      : l.match(/^(near|eq)\("([^"]+)", (.*)\)$/);
    if (!m) throw new Error(`unparsed assertion (${lang}): ${l}`);
    const rest = m[3];
    return [m[1], m[2], norm(rest.slice(rest.lastIndexOf(', ') + 2), lang)];
  });
const splitCases = (body, re) => {
  const parts = body.split(re);
  const out = [];
  for (let i = 1; i < parts.length; i += 2) out.push({ name: parts[i], code: parts[i + 1] });
  return out;
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

let caseCountGo = 0;
let caseCountSwift = 0;
let assertCount = 0;
let literalCount = 0;

const compareCases = (label, goCases, swCases) => {
  caseCountGo += goCases.length;
  caseCountSwift += swCases.length;
  if (goCases.length !== swCases.length) fail(`${label}: ${goCases.length} Go cases vs ${swCases.length} Swift cases`);
  goCases.forEach((g, i) => {
    const s = swCases[i];
    if (!s) return;
    if (g.name !== s.name) fail(`${label}[${i}]: name "${g.name}" vs "${s.name}"`);
    const gl = literals(g.code, 'go'), sl = literals(s.code, 'swift');
    if (!same(gl, sl)) fail(`${label} "${g.name}": input literals Go ${JSON.stringify(gl)} vs Swift ${JSON.stringify(sl)}`);
    literalCount += gl.length;
    const ga = asserts(g.code, 'go'), sa = asserts(s.code, 'swift');
    if (ga.length !== sa.length) fail(`${label} "${g.name}": ${ga.length} Go assertions vs ${sa.length} Swift`);
    ga.forEach((a, k) => {
      if (!same(a, sa[k])) fail(`${label} "${g.name}" #${k}: Go ${JSON.stringify(a)} vs Swift ${JSON.stringify(sa[k])}`);
    });
    assertCount += ga.length;
  });
};

// --- fixtures ----------------------------------------------------------------
for (const f of ['johnMason', 'worker']) {
  const g = literals(between(go, `func ${f}() WorkerWeek {`, '\n}', f), 'go');
  const s = literals(between(swift, `func ${f}() -> WorkerWeek {`, '\n}', f), 'swift');
  if (!same(g, s)) fail(`fixture ${f}: Go ${JSON.stringify(g)} vs Swift ${JSON.stringify(s)}`);
  literalCount += g.length;
}

// --- table tests ---------------------------------------------------------------
const goTable = (fn) => between(go, `func ${fn}(t *testing.T) {`, 'for _, tt := range tests', fn);
const GO_CASE = /\{"([^"]+)",/;
const SW_CASE = /check(?:Line|Run|Total)\("([^"]+)",/;
compareCases('ComputeLine', splitCases(goTable('TestComputeLine'), GO_CASE), splitCases(swiftFunc('testComputeLine'), SW_CASE));
compareCases('ComputeRun', splitCases(goTable('TestComputeRun'), GO_CASE), splitCases(swiftFunc('testComputeRun'), SW_CASE));
compareCases('FringeRatesTotal', splitCases(goTable('TestFringeRatesTotal'), GO_CASE), splitCases(swiftFunc('testFringeRatesTotal'), SW_CASE));

// --- RoundCents (literal strings compared exactly) ---------------------------------
{
  const g = [...goTable('TestRoundCents').matchAll(/\{(-?[\d.]+), (-?[\d.]+)\}/g)].map((m) => [m[1], m[2]]);
  const s = [...swiftFunc('testRoundCents').matchAll(/checkRound\((-?[\d.]+), (-?[\d.]+)\)/g)].map((m) => [m[1], m[2]]);
  caseCountGo += g.length;
  caseCountSwift += s.length;
  if (!same(g, s)) fail(`RoundCents: Go ${JSON.stringify(g)} vs Swift ${JSON.stringify(s)}`);
  assertCount += g.length;
}

// --- ExampleComputeLine (Go "// Output:" vs Swift eq("Output", ...)) -----------------
{
  const goBody = between(go, 'func ExampleComputeLine() {', null, 'ExampleComputeLine');
  const out = goBody.split('// Output:')[1].split('\n')
    .map((l) => l.replace(/^\s*\/\/\s?/, '').trim()).filter((l) => l && l !== '}')
    .flatMap((l) => l.split(/\s+/)).map((t) => norm(t, 'swift'));
  const swBody = swiftFunc('testExampleComputeLine');
  const sw = asserts(swBody, 'swift').map((a) => a[2]);
  caseCountGo += 1;
  caseCountSwift += 1;
  if (!same(out, sw)) fail(`ExampleComputeLine: Go output ${JSON.stringify(out)} vs Swift ${JSON.stringify(sw)}`);
  const gl = literals(goBody.split('// Output:')[0], 'go'), sl = literals(swBody, 'swift');
  if (!same(gl, sl)) fail(`ExampleComputeLine inputs: Go ${JSON.stringify(gl)} vs Swift ${JSON.stringify(sl)}`);
  assertCount += out.length;
  literalCount += gl.length;
}

console.log(`Go cases: ${caseCountGo}, Swift cases: ${caseCountSwift}, expected values: ${assertCount}, input literals: ${literalCount}`);
if (caseCountGo !== caseCountSwift) fail('case counts differ');
if (errors.length) {
  for (const e of errors) console.error(`MISMATCH ${e}`);
  process.exit(1);
}
console.log('crosscheck OK: Swift tests match wh347_test.go');
