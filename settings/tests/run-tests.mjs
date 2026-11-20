/*
 * Enthroned Settings - logic tests (F3.14).
 * Executes the DECLARATIVE contract (update-state-spec.json) with a JS
 * interpreter that mirrors the C++ interpreter semantics:
 *   - first matching transition wins;
 *   - every key in "requires" must be true in the context;
 *   - unknown events / unmatched transitions keep the current state.
 * Also executes the journal_mapping and bootc_progress tables against the
 * scenario fixtures, including the unexpected-data fixtures.
 *
 * The C++ interpreters (updatestatemachine.cpp, journalparser.cpp) implement
 * the same documented semantics; this runner proves the contract itself is
 * coherent with the fixtures. Run: node settings/tests/run-tests.mjs
 * SPDX-License-Identifier: Apache-2.0
 */
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const specPath = join(here, "..", "src", "update", "update-state-spec.json");
const scenariosDir = join(here, "..", "src", "update", "demo", "scenarios");

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
const eventTypes = new Set(spec.event_types);
check("spec: initial state exists", spec.states.includes(spec.initial));
check("spec: states unique", new Set(spec.states).size === spec.states.length);
check("spec: journal_mapping non-empty", spec.journal_mapping.length >= 5);
check("spec: bootc_progress has 4 phases",
  Object.keys(spec.bootc_progress.phases).length === 4);

for (const transition of spec.transitions) {
  check(
    `spec: transition ${transition.from} --${transition.event}--> ${transition.to} has known states`,
    spec.states.includes(transition.from) && spec.states.includes(transition.to),
  );
  check(
    `spec: transition ${transition.from} --${transition.event}--> ${transition.to} has known event`,
    eventTypes.has(transition.event),
  );
}

// ---------- Machine semantics (mirror of C++ interpreter) ----------
function step(state, event, context) {
  for (const transition of spec.transitions) {
    if (transition.from !== state || transition.event !== event.rawType) {
      continue;
    }
    const satisfied = transition.requires.every((requirement) => context[requirement] === true);
    if (satisfied) {
      return transition.to;
    }
  }
  return state;
}

// ---------- Journal mapping (mirror of C++ parser) ----------
function severityFromLevel(level) {
  if (level === "ERROR") return "Error";
  if (level === "WARN") return "Warning";
  if (level === "DEBUG") return "Debug";
  return "Info";
}

function applyJournalLine(line, state) {
  // state: { lastTask }
  const produced = [];
  let entry = null;
  try {
    entry = JSON.parse(line);
  } catch {
    entry = null;
  }
  if (entry === null || typeof entry !== "object") {
    produced.push({ rawType: "unknown-data", source: "journal", severity: "Debug" });
    return produced;
  }
  const message = entry.MESSAGE ?? "";
  let slog = null;
  if (typeof message === "string" && message.startsWith("{")) {
    try {
      slog = JSON.parse(message);
    } catch {
      slog = null;
    }
  }
  if (slog === null || typeof slog !== "object") {
    produced.push({ rawType: "unknown-data", source: "journal", severity: "Debug" });
    return produced;
  }

  const msg = slog.msg ?? "";
  const level = slog.level ?? "";
  for (const rule of spec.journal_mapping) {
    const match = rule.match ?? {};
    const eventName = rule.event;
    if (eventName === "ignore") {
      if (match.msg !== undefined && match.msg === msg) {
        return produced;
      }
      continue;
    }
    if (match.msg !== undefined && match.msg !== msg) continue;
    if (match.msgSuffix !== undefined && !msg.endsWith(match.msgSuffix)) continue;
    if (match.level !== undefined && match.level !== level) continue;
    if (match.field !== undefined && slog[match.field] !== match.equals) continue;

    const event = {
      rawType: eventName,
      severity: severityFromLevel(level),
      description: msg,
    };
    if (rule.sourceFromField !== undefined) {
      event.source = String(slog[rule.sourceFromField] ?? "").toLowerCase();
    }
    if (event.source === undefined || event.source.length === 0) {
      event.source = rule.source ?? "system";
    }
    if (rule.payloadFromField !== undefined && eventName === "bootc-progress") {
      produced.push(...applyBootcProgress(slog[rule.payloadFromField] ?? "", event.source, state));
      return produced;
    }
    // Lote 8: MESSAGE itself is the raw bootc --progress-fd JSON line
    // (enthroned-system-update helper path, no slog wrapper).
    if (rule.payloadFromMessage === true && eventName === "bootc-progress") {
      produced.push(...applyBootcProgress(message, event.source, state));
      return produced;
    }
    if (msg === "Update Check") {
      event.description = slog.update_available === true
        ? "Atualizacao disponivel"
        : "Nenhuma atualizacao disponivel";
    }
    produced.push(event);
    return produced;
  }
  produced.push({ rawType: "unknown-data", source: "journal", severity: "Debug" });
  return produced;
}

function applyBootcProgress(payload, source, state) {
  const produced = [];
  let progress = null;
  try {
    progress = JSON.parse(payload);
  } catch {
    produced.push({ rawType: "unknown-data", source, severity: "Debug" });
    return produced;
  }
  const { type, task } = progress;
  if (type !== "ProgressSteps" && type !== "ProgressBytes") {
    return produced;
  }
  const window = spec.bootc_progress.phases[task] ?? spec.bootc_progress.phases.unknown;
  const event = {
    rawType: "bootc-progress",
    source,
    phase: window.phase,
    severity: "Info",
    description: window.phase,
  };
  if (type === "ProgressBytes") {
    const bytes = Number(progress.bytes);
    const bytesTotal = Number(progress.bytesTotal);
    event.bytesTransferred = bytes;
    event.bytesTotal = bytesTotal;
    if (bytesTotal > 0) {
      event.progressPercent = window.start
        + Math.min(window.length, (bytes / bytesTotal) * window.length);
    }
  } else {
    const steps = Number(progress.steps);
    const stepsTotal = Number(progress.stepsTotal);
    if (stepsTotal >= 0) {
      event.progressPercent = window.start
        + Math.min(window.length, (steps / (stepsTotal + 1)) * window.length);
    }
  }
  if (state.lastTask === "pulling" && task !== "pulling") {
    produced.push({
      rawType: "bootc-download-finished",
      source,
      phase: "Preparing",
      severity: "Info",
      description: "Download concluido",
    });
  }
  state.lastTask = task;
  produced.push(event);
  return produced;
}

// ---------- Scenario: state machine runs ----------
for (const file of readdirSync(scenariosDir).sort()) {
  if (!file.endsWith(".json")) continue;
  const scenario = loadJson(join(scenariosDir, file));
  const name = `scenario:${scenario.name}`;

  let state = spec.initial;
  const context = {
    stagedDeployment: false,
    mutationAllowed: true,
    mutationBlocked: false,
    demoMode: true,
    freshDeployment: true,
    rollbackAvailable: true,
    offlineDetected: false,
    phaseDownloading: false,
    phasePreparing: false,
    phaseApplying: false,
  };

  for (const stepEntry of scenario.steps) {
    // context flags are updated per-event, mirroring the C++ buildContext()
    for (const rawEvent of stepEntry.events) {
      context.phaseDownloading = rawEvent.phase === "Downloading";
      context.phasePreparing = rawEvent.phase === "Preparing"
        || rawEvent.phase === "Applying" || rawEvent.phase === "Validating";
      context.phaseApplying = rawEvent.phase === "Applying";
      state = step(state, rawEvent, context);
      // A staged deployment becomes observable from the event itself on.
      if (rawEvent.rawType === "staged-deployment-detected") {
        context.stagedDeployment = true;
      }
    }
    if (stepEntry.expectState !== undefined) {
      check(`${name}: step expectState=${stepEntry.expectState}`, state === stepEntry.expectState,
        `got ${state}`);
    }
  }
  check(`${name}: finalState=${scenario.finalState}`, state === scenario.finalState,
    `got ${state}`);
}

// ---------- Scenario: unexpected-data (journal mapping contract) ----------
{
  const scenario = loadJson(join(scenariosDir, "unexpected-data.json"));
  const journalState = { lastTask: undefined };
  const events = [];
  let ignored = 0;
  for (const line of scenario.journalLines) {
    const produced = applyJournalLine(line, journalState);
    if (produced.length === 0) {
      ignored++;
      continue;
    }
    events.push(...produced);
  }

  check("unexpected-data: ignored lines counted", ignored === scenario.expectedIgnored,
    `expected ${scenario.expectedIgnored}, got ${ignored}`);

  check("unexpected-data: event count", events.length === scenario.expectedEvents.length,
    `expected ${scenario.expectedEvents.length}, got ${events.length}`);

  for (let i = 0; i < Math.min(events.length, scenario.expectedEvents.length); i++) {
    const actual = events[i];
    const expected = scenario.expectedEvents[i];
    if (expected.rawType !== undefined) {
      check(`unexpected-data: event[${i}].rawType`, actual.rawType === expected.rawType,
        `expected ${expected.rawType}, got ${actual.rawType}`);
    }
    if (expected.source !== undefined) {
      check(`unexpected-data: event[${i}].source`, actual.source === expected.source,
        `expected ${expected.source}, got ${actual.source}`);
    }
    if (expected.phase !== undefined) {
      check(`unexpected-data: event[${i}].phase`, actual.phase === expected.phase,
        `expected ${expected.phase}, got ${actual.phase}`);
    }
    if (expected.progressPercent !== undefined) {
      check(`unexpected-data: event[${i}].progressPercent`,
        actual.progressPercent !== undefined
        && Math.abs(actual.progressPercent - expected.progressPercent) < 0.01,
        `expected ~${expected.progressPercent}, got ${actual.progressPercent}`);
    }
  }

  // Sample math checks against the documented uupd/bootc windows.
  const sampleBytes = applyJournalLine(
    JSON.stringify({
      MESSAGE: JSON.stringify({
        time: "2026-11-16T04:00:03Z", level: "DEBUG", msg: "Command output",
        module: "system", status: "running",
        output: JSON.stringify({ type: "ProgressBytes", task: "pulling", bytes: 50, bytesTotal: 100 }),
      }),
    }),
    { lastTask: undefined },
  );
  check("bootc-progress: 50/100 bytes in pulling window = 40%",
    sampleBytes.length === 1 && Math.abs(sampleBytes[0].progressPercent - 40) < 0.01,
    `got ${JSON.stringify(sampleBytes)}`);

  const sampleSteps = applyJournalLine(
    JSON.stringify({
      MESSAGE: JSON.stringify({
        time: "2026-11-16T04:00:04Z", level: "DEBUG", msg: "Command output",
        module: "system", status: "running",
        output: JSON.stringify({ type: "ProgressSteps", task: "staging", steps: 5, stepsTotal: 10 }),
      }),
    }),
    { lastTask: "pulling" },
  );
  // staging window: start 90, length 10, steps 5/(10+1)=0.4545 -> 94.5454
  check("bootc-progress: staging steps 5/10 -> ~94.55%",
    sampleSteps.length === 2
    && sampleSteps[0].rawType === "bootc-download-finished"
    && Math.abs(sampleSteps[1].progressPercent - (90 + Math.min(10, (5 / 11) * 10))) < 0.01,
    `got ${JSON.stringify(sampleSteps)}`);
}

// ---------- Lote 8: system/apps separation, rollback and preflight gates ------
{
  // System-only update path reuses the update-success contract.
  check("lote8: updating + staged-deployment-detected -> restartRequired",
    step("updating", { rawType: "staged-deployment-detected" },
      { stagedDeployment: false }) === "restartRequired");
  check("lote12: unit success waits for deployment confirmation",
    step("updating", { rawType: "update-success" }, {}) === "deploymentPending");
  // Apps-only update never requires a reboot.
  check("lote8: flatpak success -> upToDate (no reboot)",
    step("updating", { rawType: "flatpak-update-success" }, {}) === "upToDate");
  check("lote8: flatpak failure -> failed",
    step("updating", { rawType: "flatpak-update-failed" }, {}) === "failed");
  check("lote8: flatpak progress keeps updating",
    step("updating", { rawType: "flatpak-progress" }, {}) === "updating");
  // Rollback is explicit, protected and produces a pending restart.
  check("lote8: rollback starts only when a previous deployment exists",
    step("updatesAvailable", { rawType: "engine-rollback-started" },
      { mutationAllowed: true, rollbackAvailable: false }) === "updatesAvailable");
  check("lote8: rollback starts with mutation + previous deployment",
    step("restartRequired", { rawType: "engine-rollback-started" },
      { mutationAllowed: true, rollbackAvailable: true }) === "rollingBack");
  check("lote8: rollback blocked without mutation",
    step("restartRequired", { rawType: "engine-rollback-started" },
      { mutationAllowed: false, rollbackAvailable: true }) === "restartRequired");
  check("lote8: rollback success -> restartRequired",
    step("rollingBack", { rawType: "rollback-success" }, {}) === "restartRequired");
  check("lote8: rollback failure -> failed",
    step("rollingBack", { rawType: "rollback-failed" }, {}) === "failed");
  // Preflight refusals never fake progress: the state is kept.
  check("lote8: preflight-blocked keeps updatesAvailable",
    step("updatesAvailable", { rawType: "preflight-blocked" }, {}) === "updatesAvailable");
  check("lote8: preflight-blocked keeps restartRequired",
    step("restartRequired", { rawType: "preflight-blocked" }, {}) === "restartRequired");
  check("lote8: staged-origin-blocked keeps the state",
    step("updatesAvailable", { rawType: "staged-origin-blocked" }, {}) === "updatesAvailable");
  // A system update that had nothing to do ends up to date.
  check("lote8: check-no-update from updating -> upToDate",
    step("updating", { rawType: "check-no-update" }, {}) === "upToDate");
  // The rollingBack state is not left behind by unrelated events.
  check("lote8: rollingBack ignores bootc-progress",
    step("rollingBack", { rawType: "bootc-progress", phase: "Downloading" },
      { phaseDownloading: true }) === "rollingBack");

  // Raw bootc --progress-fd JSON lines (enthroned-system-update path):
  // MESSAGE itself is the progress object (no uupd slog wrapper).
  const rawFd = applyJournalLine(
    JSON.stringify({
      MESSAGE: JSON.stringify({ type: "ProgressBytes", task: "pulling", bytes: 50, bytesTotal: 100 }),
    }),
    { lastTask: undefined },
  );
  check("lote8: raw --progress-fd JSON parses as bootc-progress",
    rawFd.length === 1 && rawFd[0].rawType === "bootc-progress" && rawFd[0].source === "system"
      && Math.abs(rawFd[0].progressPercent - 40) < 0.01,
    `got ${JSON.stringify(rawFd)}`);

  const rawFdSteps = applyJournalLine(
    JSON.stringify({
      MESSAGE: JSON.stringify({ type: "ProgressSteps", task: "staging", steps: 5, stepsTotal: 10 }),
    }),
    { lastTask: "pulling" },
  );
  check("lote8: raw fd staging line emits download-finished then progress",
    rawFdSteps.length === 2 && rawFdSteps[0].rawType === "bootc-download-finished",
    `got ${JSON.stringify(rawFdSteps)}`);
}

// ---------- Lote 4: local search + navigation consistency ----------
{
  const qmlDir = join(here, "..", "qml");
  const searchSource = readFileSync(join(qmlDir, "search.js"), "utf8").replace(/^\.pragma library/m, "");
  const Search = new Function(`${searchSource}; return { normalize, tokens, score, run };`)();

  const mainQml = readFileSync(join(qmlDir, "Main.qml"), "utf8");
  const indexQml = readFileSync(join(qmlDir, "SearchIndex.qml"), "utf8");

  const pages = [...mainQml.matchAll(/\{ id: "(\w+)", title: i18n\("([^"]+)"\), icon: "[^"]+", component: (\w+),\s*keywords: i18n\("([^"]+)"\)/g)]
    .map((m) => ({ id: m[1], title: m[2], component: m[3], keywords: m[4] }));
  // Lote 6: the twelve original areas plus the three Modo Simples focus
  // areas (display, sound, notifications) = 15 navigation entries.
  check("nav: 15 settings areas", pages.length === 15, `got ${pages.length}`);
  check("nav: page ids unique", new Set(pages.map((p) => p.id)).size === pages.length);
  for (const required of ["home", "system", "devices", "network", "appearance", "apps", "accounts",
    "time", "accessibility", "privacy", "updates", "about", "display", "sound", "notifications"]) {
    check(`nav: area ${required} present`, pages.some((p) => p.id === required));
  }
  for (const page of pages) {
    check(`nav: component ${page.component} declared for ${page.id}`,
      new RegExp(`Component \\{ id: ${page.component};`).test(mainQml));
  }

  const items = [...indexQml.matchAll(/\{ page: "(\w+)", title: i18n\("([^"]+)"\), icon: "[^"]+",(?: ids: \[([^\]]*)\],)?\s*keywords: i18n\("([^"]+)"\)/g)]
    .map((m) => ({
      page: m[1], title: m[2], keywords: m[4],
      ids: m[3] === undefined ? undefined : [...m[3].matchAll(/"([\w]+)"/g)].map((x) => x[1]),
    }));
  const itemBlocks = (indexQml.match(/\{ page: "/g) || []).length;
  check("search: every index item parsed", items.length === itemBlocks && items.length >= 40,
    `parsed ${items.length} of ${itemBlocks}`);
  const pageIds = new Set(pages.map((p) => p.id));
  for (const item of items) {
    check(`search: '${item.title}' targets a real page`, pageIds.has(item.page), item.page);
    check(`search: '${item.title}' module ids are kcm_* or known`,
      item.ids === undefined || (item.ids.length > 0 && item.ids.every((id) => /^(kcm_\w+|printers)$/.test(id))),
      JSON.stringify(item.ids));
  }

  const entries = [
    ...pages.map((p) => ({ title: p.title, pageTitle: "", keywords: p.keywords, page: p.id })),
    ...items.map((i) => ({ title: i.title, pageTitle: pages.find((p) => p.id === i.page).title,
      keywords: i.keywords, page: i.page, ids: i.ids })),
  ];
  const first = (q) => (Search.run(entries, q, 30)[0] || {}).title;
  const top = (q, n = 3) => Search.run(entries, q, 30).slice(0, n).map((e) => e.title);

  check("search: accents and case ignored", Search.normalize("Resolução ÁÇÃO") === "resolucao acao");
  check("search: empty query finds nothing", Search.run(entries, "   ", 30).length === 0);
  check("search: nonsense finds nothing", Search.run(entries, "xyzzyqq", 30).length === 0);
  // Lote 6.1: source strings are English msgids (the pt_BR catalog carries the
  // Portuguese translations), so the static expectations below use the msgids.
  check("search: wifi -> network connections", first("wifi") === "Wi-Fi and network connections", first("wifi"));
  check("search: 'wi-fi' equals 'wifi'", first("wi-fi") === first("wifi"));
  check("search: bluetooth", first("bluetooth") === "Bluetooth", first("bluetooth"));
  check("search: dark mode -> theme", top("dark mode").includes("Light and dark theme"), top("dark mode").join("|"));
  check("search: wallpaper synonym", top("wallpaper").includes("Wallpaper"), top("wallpaper").join("|"));
  check("search: resolution -> Display", top("resolution").includes("Display"), top("resolution").join("|"));
  check("search: time zone -> Date and time", top("time zone").includes("Date and time"), top("time zone").join("|"));
  check("search: printer -> printers", top("print").includes("Printers"), top("print").join("|"));
  check("search: hostname -> device name", top("hostname").includes("Device name"), top("hostname").join("|"));
  check("search: gpu -> device specs", top("gpu").includes("Device specifications"), top("gpu").join("|"));
  check("search: flatpak reaches updates and apps",
    Search.run(entries, "flatpak", 30).some((e) => e.page === "updates")
      && Search.run(entries, "flatpak", 30).some((e) => e.page === "apps"));
  check("search: all words must match", first("screen lock") === "Screen locking", first("screen lock"));
  check("search: title prefix beats keyword", first("display") === "Display", first("display"));
  check("search: limit respected", Search.run(entries, "a", 5).length <= 5);
}

// ---------- Lote 6.1: pt_BR catalog covers the search/nav source strings ------
{
  const qmlDir = join(here, "..", "qml");
  const poPath = join(here, "..", "..", "build_files", "l10n", "pt_BR", "enthroned-settings.po");
  const poText = readFileSync(poPath, "utf8");
  const msgids = new Set();
  const lines = poText.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^msgid "((?:[^"\\]|\\.)*)"/);
    if (!m) continue;
    let value = m[1];
    while (i + 1 < lines.length && lines[i + 1].startsWith('"')) {
      i++;
      value += lines[i].match(/^"((?:[^"\\]|\\.)*)"/)[1];
    }
    if (value.length > 0) msgids.add(value);
  }
  check("i18n catalog: settings .po parses", msgids.size >= 400, String(msgids.size));

  const unquote = (s) => s.replace(/\\"/g, '"').replace(/\\n/g, "\n").replace(/\\\\/g, "\\");
  const literals = [];
  for (const file of ["Main.qml", "SearchIndex.qml"]) {
    const text = readFileSync(join(qmlDir, file), "utf8");
    for (const m of text.matchAll(/\bi18n\("((?:[^"\\]|\\.)*)"/g)) {
      literals.push(unquote(m[1]));
    }
  }
  check("i18n catalog: literals extracted", literals.length >= 130, String(literals.length));
  const missing = [...new Set(literals)].filter((s) => !msgids.has(s));
  check("i18n catalog: every Main/SearchIndex msgid is in the pt_BR catalog",
    missing.length === 0, JSON.stringify(missing.slice(0, 5)));
}

// ---------- Lote 11B (H5 P2-5): honest state presentation --------------------
{
  // Reading the deployment status (bootc-status-ok) is NOT an update check:
  // it must never present "Sistema atualizado" from a mere version read, and
  // must never heal a failed/offline/unavailable check behind the user's back.
  check("lote11b: unknown + bootc-status-ok stays unknown (never verified)",
    step("unknown", { rawType: "bootc-status-ok" }, {}) === "unknown");
  check("lote11b: failed check is not healed by bootc-status-ok",
    step("failed", { rawType: "bootc-status-ok" }, {}) === "failed");
  check("lote11b: noNetwork is not healed by bootc-status-ok",
    step("noNetwork", { rawType: "bootc-status-ok" }, {}) === "noNetwork");
  check("lote11b: serviceUnavailable is not healed by bootc-status-ok",
    step("serviceUnavailable", { rawType: "bootc-status-ok" }, {}) === "serviceUnavailable");
  check("lote11b: upToDate stays upToDate on bootc-status-ok",
    step("upToDate", { rawType: "bootc-status-ok" }, {}) === "upToDate");
  check("lote11b: checking stays checking on bootc-status-ok",
    step("checking", { rawType: "bootc-status-ok" }, {}) === "checking");
  for (const from of ["unknown", "upToDate"]) {
    check(`lote11b: ${from} + bootc-status-ok with staged deployment -> restartRequired`,
      step(from, { rawType: "bootc-status-ok" }, { stagedDeployment: true }) === "restartRequired");
  }
  // Only a real check result may reach upToDate from unknown.
  check("lote11b: unknown + engine-check-started -> checking",
    step("unknown", { rawType: "engine-check-started" }, {}) === "checking");
  check("lote11b: check-no-update is the honest path to upToDate",
    step("checking", { rawType: "check-no-update" }, {}) === "upToDate");
  check("lote11b: check-failed from checking -> failed",
    step("checking", { rawType: "check-failed" }, {}) === "failed");
  // Full honest H5 sequence: open center (status read), run a failing check,
  // refresh the status again — the title must not say "up to date" anywhere.
  let h5 = spec.initial;
  h5 = step(h5, { rawType: "bootc-status-ok" }, {});
  h5 = step(h5, { rawType: "engine-check-started" }, {});
  h5 = step(h5, { rawType: "check-failed" }, {});
  h5 = step(h5, { rawType: "bootc-status-ok" }, {});
  check("lote11b: H5 sequence ends honest (failed, not upToDate)", h5 === "failed", `got ${h5}`);
}

// ---------- Lote 12: deployment confirmation after a system update ---------
{
  const pending = "deploymentPending";
  for (const from of ["unknown", "updating", "preparing", "upToDate"]) {
    check(`lote12: ${from} + unit success enters pending, even with stale staging`,
      step(from, { rawType: "update-success" }, { stagedDeployment: true }) === pending);
  }
  for (const rawType of ["bootc-status-ok", "bootc-status-unavailable",
    "staged-deployment-detected", "deployment-confirmed", "check-no-update"]) {
    check(`lote12: ${rawType} without fresh deployment keeps confirmation pending`,
      step(pending, { rawType }, {}) === pending);
  }
  check("lote12: fresh staged deployment requests restart",
    step(pending, { rawType: "staged-deployment-detected" }, { freshDeployment: true })
      === "restartRequired");
  check("lote12: fresh status without staging confirms only the update command",
    step(pending, { rawType: "deployment-confirmed" }, { freshDeployment: true })
      === "updateConfirmed");
  check("lote12: cache re-read without staging does not clear restart",
    step("restartRequired", { rawType: "bootc-status-ok" }, {}) === "restartRequired");
  check("lote12: offline check remains a check failure",
    step("checking", { rawType: "check-failed" }, { offlineDetected: true }) === "noNetwork");
  check("lote12: late boot publication does not interrupt a running check",
    step("checking", { rawType: "staged-deployment-detected" }, {}) === "checking");
  check("lote12: failed update stays failed after reading boot status",
    step(step("updating", { rawType: "update-failed-with-errors" }, {}),
      { rawType: "bootc-status-ok" }, {}) === "failed");
}

// ---------- Gate 12.4: a failed operation and pending restart are both visible ----------
{
  const page = readFileSync(join(here, "..", "qml", "pages", "UpdatesPage.qml"), "utf8");
  const restartMessage = page.match(/visible: ([^\r\n]+)\s+type: Kirigami\.MessageType\.Warning\s+icon\.name: "system-reboot"/);
  const failureMessage = page.match(/visible: ([^\r\n]+)\s+type: Kirigami\.MessageType\.Error\s+icon\.name: "dialog-error"/);
  const restartButton = page.match(/text: i18n\("Restart"\)\s+icon\.name: "system-reboot"\s+visible: ([^\r\n]+)/);
  const visible = (binding, updates) => binding && Function("updates", `return (${binding[1]});`)(updates);

  const staged = step(spec.initial, { rawType: "staged-deployment-detected" }, { stagedDeployment: true });
  const updating = step(staged, { rawType: "engine-update-started" }, { mutationAllowed: true });
  const failedUpdate = step(updating, { rawType: "update-failed-with-errors" }, { stagedDeployment: true });
  check("gate12.4: staged deployment starts in restartRequired", staged === "restartRequired");
  check("gate12.4: failed second operation shows the error", visible(failureMessage, { state: failedUpdate }));
  const unavailable = step(staged, { rawType: "systemd-unavailable" }, { stagedDeployment: true });
  check("gate12.4: attempting a check without systemd shows serviceUnavailable", unavailable === "serviceUnavailable");
  for (const from of [failedUpdate, "noNetwork", unavailable]) {
    for (const rawType of ["bootc-status-ok", "bootc-status-unavailable", "staged-deployment-detected"]) {
      check(`gate12.4: ${rawType} preserves the ${from} operation state`,
        step(from, { rawType }, { stagedDeployment: true }) === from);
    }
  }
  check("gate12.4: a cleared deployment gives no positive check result",
    step(staged, { rawType: "staged-deployment-cleared" }, {}) === "unknown");
  check("gate12.4: clearing staging preserves the failure",
    step(failedUpdate, { rawType: "staged-deployment-cleared" }, {}) === "failed");
  for (const [label, binding] of [["warning", restartMessage], ["button", restartButton]]) {
    check(`gate12.4: pending restart ${label} remains visible after a failed operation`,
      visible(binding, { state: failedUpdate, restartPending: true }), `state=${failedUpdate}`);
    check(`gate12.4: pending restart ${label} is visible on reopening with staging`,
      visible(binding, { state: staged, restartPending: true }));
    check(`gate12.4: pending restart ${label} is visible when systemd is unavailable`,
      visible(binding, { state: unavailable, restartPending: true }));
    check(`gate12.4: pending restart ${label} is hidden after the resulting boot`,
      visible(binding, { state: spec.initial, restartPending: false }) === false);
  }
  check("gate12.4: the restart action is gated by canReboot",
    /text: i18n\("Restart"\)\s+icon\.name: "system-reboot"\s+visible: [^\r\n]+\s+enabled: updates\.canReboot/.test(page));
  const channel = loadJson(join(here, "..", "..", "system_files", "usr", "share", "enthroned-os", "release-channel.json"));
  check("gate12.4: production channel stays closed", channel.channel === "f1-dev"
    && channel.production_ready === false && channel.expected_image_references.length === 0
    && channel.publish_registry === null);

  const poPath = join(here, "..", "..", "build_files", "l10n", "pt_BR", "enthroned-settings.po");
  const po = readFileSync(poPath, "utf8");
  const translations = new Map([...po.matchAll(/^msgid ("[^"\r\n]+")\r?\nmsgstr ("[^"\r\n]+")/gm)]
    .map(([, msgid, msgstr]) => [JSON.parse(msgid), JSON.parse(msgstr)]));
  for (const [msgid, expected] of [
    ["A restart is still required for the staged change. Save your work before restarting.",
      "A reinicialização continua necessária para aplicar a alteração preparada. Salve seu trabalho antes de reiniciar."],
    ["The last operation ended with an error. See the details and try again.",
      "A última operação terminou com erro. Veja os detalhes e tente novamente."],
    ["Restart", "Reinicializar"],
    ["Restart required", "Reinicialização necessária"],
    ["Failed", "Falha"],
    ["Service unavailable", "Serviço indisponível"],
    ["Update finished with errors", "Atualização com erros"],
    ["Update availability unknown", "Disponibilidade de atualizações desconhecida"],
  ]) {
    check(`gate12.4: pt_BR displays '${expected}'`,
      page.includes(`i18n(${JSON.stringify(msgid)})`) && translations.get(msgid) === expected);
  }
}

// ---------- Report ----------
console.log(`PASS ${passed} / FAIL ${failed}`);
if (failed > 0) {
  for (const failure of failures) {
    console.error(`FAIL: ${failure}`);
  }
  process.exit(1);
}
