#!/usr/bin/env node
/*
 * Lote 9.2 (H4-002 / H4-011) - regression test for the desktop-shortcut
 * command built by the launcher. Imports the SAME ShortcutCommand.js module
 * AppActions.qml uses (no copy): validation allowlist, POSIX quoting, the
 * connect/disconnect cycle and the "create, remove, create again" flow.
 *
 * Run: node scripts/test-launcher-appactions.mjs
 * SPDX-License-Identifier: Apache-2.0
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
let source = readFileSync(join(root,
    "system_files/usr/share/plasma/plasmoids/org.enthroned.launcher/contents/ui/ShortcutCommand.js"),
    "utf8");
// The QML .pragma directive is meaningless to Node; a .pragma library
// implicitly exports its functions, so the test adds an explicit export.
source = source.replace(/^\.pragma library.*$/m, "");
source += "\nexport { helper, isValidStorageId, shellQuote, buildCommand, request, consume };\n";

const mod = await import(`data:text/javascript;charset=utf-8,${encodeURIComponent(source)}`);

let failures = 0;
function expect(desc, actual, expected) {
    const ok = JSON.stringify(actual) === JSON.stringify(expected);
    console.log(`${ok ? "PASS" : "FAIL"}: ${desc}`);
    if (!ok) {
        console.log(`  expected ${JSON.stringify(expected)}`);
        console.log(`  actual   ${JSON.stringify(actual)}`);
        ++failures;
    }
}

function fakeRunner() {
    return {
        connected: [],
        disconnected: [],
        connectSource(source) { this.connected.push(source); },
        disconnectSource(source) { this.disconnected.push(source); },
    };
}

// ---- H4-002: the id can never smuggle a second command into the shell ----
const validIds = [
    "org.kde.dolphin.desktop",
    "ai.storyteller.artcraft-launcher.desktop",
    "com.example.App_1.desktop",
];
const invalidIds = [
    "",
    "app",
    "app.txt",
    ".hidden.desktop",
    "-app.desktop",
    "app..desktop",
    "org.kde.dolphin.desktop ",
    " org.kde.dolphin.desktop",
    "a b.desktop",
    "a;b.desktop",
    "a'b.desktop",
    'a"b.desktop',
    "a\\b.desktop",
    "a/b.desktop",
    "../passwd.desktop",
    "../../x.desktop",
    "a|b.desktop",
    "a&b.desktop",
    "$(touch shell-boundary).desktop",
    "`touch shell-boundary`.desktop",
    "a\nb.desktop",
    "app.desktop\n",
    "applications:app.desktop",
    123,
    null,
    undefined,
];

for (const id of invalidIds) {
    const runner = fakeRunner();
    const pending = mod.request(runner, "", id);
    expect(`invalid id rejected: ${JSON.stringify(id)}`,
        [pending, runner.connected.length, runner.disconnected.length], ["", 0, 0]);
}

for (const id of validIds) {
    const runner = fakeRunner();
    const pending = mod.request(runner, "", id);
    expect(`valid id becomes one quoted command: ${id}`,
        [pending, runner.connected], [`enthroned-desktop-shortcut '${id}'`, [pending]]);
    const boundary = /['"`;$&|\\]|\$\(/.test(pending.replace(/^enthroned-desktop-shortcut '/, "").replace(/'$/, "").replace(/'\\''/g, ""));
    expect(`no unquoted metacharacter reaches the shell: ${id}`, boundary, false);
}

// Quote escaping stays correct even for text the allowlist would reject.
expect("POSIX single-quote escaping", mod.shellQuote("it's"), "'it'\\''s'");

// ---- H4-011: the helper can run again in the same popup instance ----
{
    // create -> result -> remove -> create again: TWO helper executions.
    const runner = fakeRunner();
    let pending = mod.request(runner, "", "a.desktop");
    expect("first create connects the helper", [runner.connected], [[pending]]);
    pending = mod.consume(runner, pending, pending);
    expect("result consumed disconnects the source", [pending, runner.disconnected.length], ["", 1]);
    pending = mod.request(runner, pending, "a.desktop");
    expect("second create runs the helper again",
        [runner.connected.length, runner.disconnected.length, pending !== ""], [2, 1, true]);
}

{
    // A failed first attempt (error result) also disconnects, so a retry runs.
    const runner = fakeRunner();
    let pending = mod.request(runner, "", "a.desktop");
    pending = mod.consume(runner, pending, pending); // error consumed as well
    pending = mod.request(runner, pending, "a.desktop");
    expect("retry after failure runs the helper again", [runner.connected.length], [2]);
}

{
    // A new request while one is pending drops the previous source first.
    const runner = fakeRunner();
    const first = mod.request(runner, "", "a.desktop");
    const second = mod.request(runner, first, "b.desktop");
    expect("pending source is replaced",
        [runner.disconnected, second], [[first], `enthroned-desktop-shortcut 'b.desktop'`]);
    // The stale result of the replaced source cannot clear the new one.
    const after = mod.consume(runner, second, first);
    expect("stale result leaves the pending command alone", [after], [second]);
    mod.consume(runner, second, second);
    expect("fresh result clears the pending command", [runner.disconnected.length], [2]);
}

{
    // Malformed ids during a pending operation cancel it without connecting.
    const runner = fakeRunner();
    const pending = mod.request(runner, "", "a.desktop");
    const after = mod.request(runner, pending, "a;b.desktop");
    expect("invalid request cancels the pending source without connecting",
        [after, runner.connected.length, runner.disconnected], ["", 1, [pending]]);
}

if (failures > 0) {
    console.error(`FAILED: ${failures} case(s)`);
    process.exit(1);
}
console.log("ALL CHECKS PASSED");
