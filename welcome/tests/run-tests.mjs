/*
 * Enthroned Welcome - logic tests (F4.13).
 * Executes the DECLARATIVE contract (welcome-state-spec.json) with a JS
 * interpreter mirroring the C++ controller semantics (welcomecontroller.cpp):
 *   - first matching transition wins; unmatched events keep the state;
 *   - notifyLaunched picks first-launch (never-started) or resume (interrupted);
 *   - consent/decline side-effects move the persisted artcraft fields together
 *     with the phase; absence of a choice is never consent;
 *   - launch policy: autostart shows unless completed or dismissed,
 *     manual always shows, a second instance never shows;
 *   - persistence sanitization resets anything invalid to the initial state;
 *   - the optional installer contract is replayed from fixtures (gate,
 *     checksum, offline) with NO network and NO real installation.
 * The C++ controller implements the same documented semantics; this runner
 * proves the contract is coherent with the fixtures.
 * Run: node welcome/tests/run-tests.mjs
 * SPDX-License-Identifier: Apache-2.0
 */
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const specPath = join(here, "..", "src", "welcome-state-spec.json");
const scenariosDir = join(here, "scenarios");

let passed = 0;
let failed = 0;
const failures = [];

function check(name, condition, detail) {
  if (condition) {
    passed++;
  } else {
    failed++;
    failures.push(`${name}${detail ? ` — ${detail}` : ""}`);
  }
}

function loadJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

// ---------- Spec self-consistency ----------
const spec = loadJson(specPath);
const states = new Set(spec.states);
const eventTypes = new Set(spec.event_types);
check("spec: initial state exists", states.has(spec.initial));
check("spec: states unique", new Set(spec.states).size === spec.states.length);
check("spec: 8 walkthrough states", spec.states.length === 8);
check("spec: installer states known",
  spec.installer.states.every((s) => typeof s === "string") && spec.installer.states.length === 8);
check("spec: installer gate declared",
  spec.installer.env_gate === "ENTHRONED_WELCOME_ALLOW_INSTALL"
  && spec.installer.default_when_gate_closed === "blocked");
check("spec: consent required, checkbox unchecked by default",
  spec.installer.consent_required === true && spec.installer.default_checkbox === false);
check("spec: apps actions require availability",
  spec.apps_policy.launch_action_requires_available === true
  && spec.apps_policy.no_fake_controls === true);
check("spec: profile apply requires explicit action",
  spec.profile_policy.apply_requires_explicit_action === true
  && spec.profile_policy.no_auto_apply_on_open === true);

const installerStates = new Set(spec.installer.states);
for (const t of spec.transitions) {
  check(`spec: transition ${t.from} --${t.event}--> ${t.to} known`,
    states.has(t.from) && states.has(t.to) && eventTypes.has(t.event));
}
for (const t of spec.installer.transitions) {
  check(`spec: installer transition ${t.from} --${t.event}--> ${t.to} known`,
    installerStates.has(t.from) && installerStates.has(t.to));
}

// ---------- Semantics mirrored from welcomecontroller.cpp ----------
function step(state, event) {
  for (const t of spec.transitions) {
    if (t.from === state && t.event === event) {
      return t.to;
    }
  }
  return state;
}

function installerStep(state, event) {
  for (const t of spec.installer.transitions) {
    if (t.from === state && t.event === event) {
      return t.to;
    }
  }
  return state;
}

function shouldShowOnLaunch(phase, source, alreadyRunning) {
  if (alreadyRunning) return false;
  if (source === "manual") return true;
  return !spec.launch_decision.autostart_shows_unless.includes(phase);
}

function sanitizePersistence(raw) {
  let parsed = {};
  let valid = false;
  try {
    parsed = JSON.parse(raw);
    valid = typeof parsed === "object" && parsed !== null && !Array.isArray(parsed);
  } catch {
    valid = false;
  }
  // The record is trusted only as a whole (mirror of WelcomeController::sanitize):
  // an unknown phase or wrong version resets every field to the initial state.
  const coherent = valid && parsed.version === 1 && states.has(parsed.phase);
  const phase = coherent ? parsed.phase : spec.initial;
  const page = coherent && Number.isInteger(parsed.currentPage) && parsed.currentPage >= 0
    && parsed.currentPage <= 4 ? parsed.currentPage : 0;
  const consented = coherent && parsed.artcraftConsented === true;
  const installState = coherent && ["idle", "pending", "done", "failed"].includes(parsed.artcraftInstallState)
    ? parsed.artcraftInstallState : "idle";
  return { phase, currentPage: page, artcraftConsented: consented, artcraftInstallState: installState };
}

// Drives one scenario through the machine + optional installer replay.
function runScenario(s) {
  let phase = sanitizePersistence(JSON.stringify({ version: 1, phase: spec.initial })).phase;
  let consented = false;
  let installState = "idle";
  let page = 0;
  let installerState = "idle";

  const before = s.installer && s.installer.gate === "open" ? installerState : installerState;
  if (s.installer) {
    if (s.installer.gate !== "open") {
      installerState = installerStep(installerState, "gate-closed");
    } else {
      for (const ev of s.installer.steps) {
        installerState = installerStep(installerState, ev);
      }
    }
  }

  for (const stepDef of s.steps ?? []) {
    if (typeof stepDef.page === "number") {
      page = stepDef.page;
      continue;
    }
    const event = stepDef.event;
    if (event === "notify") {
      if (phase === "never-started") {
        phase = step(phase, "first-launch");
      } else if (phase === "interrupted") {
        phase = step(phase, "resume");
      }
    } else if (event === "consent") {
      consented = true;
      if (installState === "idle") installState = "pending";
      phase = step(phase, "artcraft-consent");
    } else if (event === "decline") {
      consented = false;
      installState = "idle";
      phase = step(phase, "artcraft-decline");
    } else if (event === "artcraft-success") {
      installState = "done";
      phase = step(phase, "artcraft-success");
    } else if (event === "artcraft-failure") {
      installState = "failed";
      phase = step(phase, "artcraft-failure");
    } else if (event === "retry") {
      if (consented) installState = "pending";
      phase = step(phase, "artcraft-retry");
    } else if (event === "finish") {
      if (page === 4) phase = step(phase, "finish");
    } else {
      phase = step(phase, event);
    }
  }

  return { phase, consented, installState, page, installerState, before };
}

// ---------- Scenarios ----------
const files = readdirSync(scenariosDir).filter((f) => f.endsWith(".json")).sort();
check("scenarios: 20 fixtures present", files.length === 20, String(files.length));

for (const file of files) {
  const s = loadJson(join(scenariosDir, file));
  const name = s.name ?? file;

  if (s.kind === "decision") {
    for (const c of s.cases) {
      const got = shouldShowOnLaunch(c.phase, c.source, c.alreadyRunning);
      check(`${name}: ${c.source}/phase=${c.phase}/running=${c.alreadyRunning}`,
        got === c.expectedShow, `got ${got}`);
    }
    continue;
  }

  if (s.kind === "persistence") {
    for (const c of s.cases) {
      const got = sanitizePersistence(c.json);
      const ok = Object.entries(c.expected).every(([k, v]) => got[k] === v);
      check(`${name}: ${c.label}`, ok, JSON.stringify(got));
      if (c.autostartShouldShow !== undefined) {
        check(`${name}: ${c.label} autostart`,
          shouldShowOnLaunch(got.phase, "autostart", false) === c.autostartShouldShow);
      }
    }
    continue;
  }

  if (s.kind === "uipolicy") {
    for (const rule of s.rules) {
      const text = readFileSync(join(here, "..", rule.file), "utf8");
      for (const needle of rule.contains ?? []) {
        check(`${name}: ${rule.file} contains "${needle}"`, text.includes(needle));
      }
      for (const needle of rule.notContains ?? []) {
        check(`${name}: ${rule.file} does NOT contain "${needle}"`, !text.includes(needle));
      }
    }
    continue;
  }

  // machine (and optional installer) scenario
  const got = runScenario(s);
  const expected = s.expected;
  check(`${name}: final phase`, got.phase === expected.phase, `got ${got.phase}`);
  if (expected.artcraftConsented !== undefined) {
    check(`${name}: artcraftConsented`, got.consented === expected.artcraftConsented,
      `got ${got.consented}`);
  }
  if (expected.artcraftInstallState !== undefined) {
    check(`${name}: artcraftInstallState`, got.installState === expected.artcraftInstallState,
      `got ${got.installState}`);
  }
  if (expected.autostartShouldShow !== undefined) {
    check(`${name}: autostartShouldShow`,
      shouldShowOnLaunch(got.phase, "autostart", false)
        === expected.autostartShouldShow);
  }
  if (expected.finalPage !== undefined) {
    check(`${name}: finalPage`, got.page === expected.finalPage, `got ${got.page}`);
  }
  if (expected.installerState !== undefined) {
    check(`${name}: installerState`, got.installerState === expected.installerState,
      `got ${got.installerState}`);
  }
}

// ---------- Report ----------
console.log(`\nWelcome logic tests: ${passed} passed, ${failed} failed`);
if (failures.length > 0) {
  for (const f of failures) {
    console.log(`  FAIL: ${f}`);
  }
  process.exit(1);
}
