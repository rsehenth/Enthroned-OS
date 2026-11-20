// Gate 12.2: evaluates the REAL polkit rule files (base + Enthroned) with polkit's
// documented semantics (files sorted by name, /etc shadows /usr/share on the same
// name, the first non-empty result wins) for subjects that a container cannot
// provide (logind session: local/active). Usage: node polkit-rules-harness.js <dir>...
// SPDX-License-Identifier: Apache-2.0
"use strict";
const fs = require("fs");
const path = require("path");

const Result = { NO: "no", YES: "yes", AUTH_SELF: "auth_self", AUTH_SELF_KEEP: "auth_self_keep",
                 AUTH_ADMIN: "auth_admin", AUTH_ADMIN_KEEP: "auth_admin_keep", NOT_HANDLED: "" };

function loadRules(dirs) {
    const files = new Map(); // basename -> full path; later directories shadow earlier ones
    for (const dir of dirs) {
        if (!fs.existsSync(dir)) continue;
        for (const name of fs.readdirSync(dir)) {
            if (name.endsWith(".rules")) files.set(name, path.join(dir, name));
        }
    }
    const rules = [];
    const loadErrors = [];
    for (const name of [...files.keys()].sort()) {
        const polkit = {
            Result,
            addRule: (fn) => rules.push({ file: name, fn }),
            addAdminRule: () => {},
            log: () => {},
            spawn: () => "",
            runtimeInit: () => {},
        };
        try {
            new Function("polkit", fs.readFileSync(files.get(name), "utf8"))(polkit);
        } catch (error) {
            loadErrors.push(`${name}: ${error.message}`);
        }
    }
    return { rules, loadErrors };
}

function decide(rules, details, subject) {
    const action = { id: details.id, lookup: (key) => details[key] };
    const who = {
        user: subject.user || "u",
        local: !!subject.local,
        active: !!subject.active,
        isInGroup: (group) => (subject.groups || []).includes(group),
    };
    for (const { file, fn } of rules) {
        let value;
        try { value = fn(action, who); } catch (error) { continue; }
        if (typeof value === "string" && value !== "") return { value, file };
    }
    return { value: "not_handled", file: null };
}

const { rules, loadErrors } = loadRules(process.argv.slice(2));
let pass = 0, fail = 0;
function expect(label, details, subject, wanted) {
    const got = decide(rules, details, subject).value;
    const ok = got === wanted;
    ok ? pass++ : fail++;
    console.log(`${ok ? "PASS" : "FAIL"}  ${label}  => ${got}${ok ? "" : ` (wanted ${wanted})`}`);
}

const MU = "org.freedesktop.systemd1.manage-units";
const act = (unit, verb) => ({ id: MU, unit, verb });
const trusted = { local: true, active: true, groups: ["wheel"] };
const subjects = {
    "wheel local active": trusted,
    "wheel local INACTIVE": { local: true, active: false, groups: ["wheel"] },
    "wheel REMOTE": { local: false, active: true, groups: ["wheel"] },
    "non-wheel local active": { local: true, active: true, groups: ["users"] },
    "non-wheel remote": { local: false, active: false, groups: [] },
    "no groups, no session": { groups: [] },
};

console.log(`rules loaded: ${rules.length} (files: ${[...new Set(rules.map((r) => r.file))].length}), load errors: ${loadErrors.length}`);
for (const e of loadErrors) console.log("LOAD-ERROR " + e);

// --- positive: the Update Center path stays passwordless --------------------------------
expect("Update Center: wheel local active starts uupd-manual.service", act("uupd-manual.service", "start"), trusted, Result.YES);
expect("wheel local active starts uupd.service (upstream parity)", act("uupd.service", "start"), trusted, Result.YES);

// --- negative: everyone else, every other verb --------------------------------------------
for (const unit of ["uupd.service", "uupd-manual.service"]) {
    for (const verb of ["stop", "restart", "kill", "reload", "reset-failed", "set-property", "try-restart", "reload-or-restart"]) {
        expect(`trusted subject cannot ${verb} ${unit} without authentication`, act(unit, verb), trusted, Result.AUTH_ADMIN);
    }
    for (const [name, subject] of Object.entries(subjects)) {
        if (subject === trusted) continue;
        expect(`${name}: start ${unit} needs authentication`, act(unit, "start"), subject, Result.AUTH_ADMIN);
        expect(`${name}: stop ${unit} needs authentication`, act(unit, "stop"), subject, Result.AUTH_ADMIN);
    }
}
expect("missing verb detail fails closed", { id: MU, unit: "uupd-manual.service" }, trusted, Result.AUTH_ADMIN);
expect("unexpected verb casing fails closed", act("uupd-manual.service", "START"), trusted, Result.AUTH_ADMIN);

// --- preserved: empower, Enthroned units, other base rules, lookalike names ------------------
const empower = { local: false, active: false, groups: ["empower"] };
expect("run0 --empower user keeps YES through empower.rules", act("uupd.service", "stop"), empower, Result.YES);
for (const unit of ["enthroned-update-check.service", "enthroned-system-update.service",
                    "enthroned-flatpak-update.service", "enthroned-rollback.service"]) {
    expect(`Enthroned rule intact: wheel local active ${unit}`, act(unit, "start"), trusted, Result.YES);
    expect(`Enthroned rule intact: non-wheel ${unit} not granted`, act(unit, "start"), subjects["non-wheel local active"], "not_handled");
}
expect("ublue-rebase@ rule intact for wheel", act("ublue-rebase@x.service", "start"), { groups: ["wheel"] }, Result.YES);
expect("ublue-rebase@ rule intact: non-wheel not granted", act("ublue-rebase@x.service", "start"), subjects["no groups, no session"], "not_handled");
expect("unrelated unit untouched (trusted)", act("sshd.service", "start"), trusted, "not_handled");
expect("unrelated unit untouched (anyone)", act("sshd.service", "stop"), subjects["no groups, no session"], "not_handled");
for (const unit of ["uupd.service ", " uupd.service", "UUPD.service", "uupd.service\n", "uupd-manual.service.d",
                    "uupd.timer", "../uupd.service", "uupd.service@x", "uupd\u0000.service"]) {
    expect(`lookalike unit ${JSON.stringify(unit)} is not granted`, act(unit, "start"), subjects["no groups, no session"], "not_handled");
}
expect("other manage-units-like action untouched", { id: "org.freedesktop.systemd1.reload-daemon", unit: "uupd.service", verb: "start" }, subjects["no groups, no session"], "not_handled");

console.log(`\nharness: ${pass} passed, ${fail} failed`);
process.exit(fail || loadErrors.length ? 1 : 0);
