#!/usr/bin/env node
/*
 * Lote 9.2 (H4-003) - regression test for the launcher app-list filter.
 * Extracts the REAL filterRowCallback from FullRepresentation.qml (no copy,
 * no text assertion) and executes it against a minimal KSortFilterProxyModel
 * harness: duplicates, repeated re-evaluation, category switches back and
 * forth, invalidation between switches and shared applications across
 * categories. The list must stay stable and every app must appear once.
 *
 * Run: node scripts/test-launcher-filter.mjs
 * SPDX-License-Identifier: Apache-2.0
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const qml = readFileSync(join(root,
    "system_files/usr/share/plasma/plasmoids/org.enthroned.launcher/contents/ui/FullRepresentation.qml"),
    "utf8");

// Extract the arrow function assigned to filterRowCallback by brace matching.
const marker = qml.indexOf("filterRowCallback:");
if (marker < 0) {
    console.error("FAIL: filterRowCallback not found in FullRepresentation.qml");
    process.exit(1);
}
const bodyStart = qml.indexOf("{", qml.indexOf("=>", marker));
let depth = 0, bodyEnd = -1;
for (let i = bodyStart; i < qml.length; ++i) {
    if (qml[i] === "{") ++depth;
    else if (qml[i] === "}") { --depth; if (depth === 0) { bodyEnd = i; break; } }
}
if (bodyEnd < 0) {
    console.error("FAIL: could not extract filterRowCallback");
    process.exit(1);
}
const arrowSource = qml.slice(qml.indexOf("(", marker), bodyEnd + 1);

const FAV_ROLE = 1;
let currentModel = null;
const dedupeProxy = {
    favRole: FAV_ROLE,
    get sourceModel() { return currentModel; },
};
const fullRep = { modelRevision: 0 };
const predicate = new Function("dedupeProxy", "fullRep", `return (${arrowSource});`)(dedupeProxy, fullRep);

function makeModel(ids) {
    return {
        index(row) { return { row }; },
        data(index, role) {
            if (role !== FAV_ROLE) return null;
            return ids[index.row] ?? null;
        },
    };
}
// Runs a full accept-row pass like KSortFilterProxyModel does.
function filterAll(ids) {
    currentModel = makeModel(ids);
    return ids.map((_, row) => predicate(row, undefined));
}

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

// 1. Audit reproduction: duplicates keep the first row only.
const dup = ["app.desktop", "app.desktop", "other.desktop"];
expect("duplicates: first kept, second dropped", filterAll(dup), [true, false, true]);

// 2. Re-evaluating the SAME rows must not change any result (the old
//    stateful callback flipped true->false on re-evaluation).
expect("re-evaluation is stable", dup.map((_, row) => predicate(row, undefined)), [true, false, true]);
expect("re-evaluation is stable (again)", dup.map((_, row) => predicate(row, undefined)), [true, false, true]);

// 3. Category switches back and forth (audit sequence: Todos -> categoria ->
//    outra categoria -> Todos) with shared apps. No state may leak between
//    models; the old bug returned false for the single row of a new model.
expect("category A", filterAll(["a.desktop", "b.desktop"]), [true, true]);
expect("category B (shared apps, new order)", filterAll(["b.desktop", "a.desktop", "c.desktop"]), [true, true, true]);
expect("back to category A", filterAll(["a.desktop", "b.desktop"]), [true, true]);
expect("back to category B", filterAll(["b.desktop", "a.desktop", "c.desktop"]), [true, true, true]);
expect("single-app category is visible", filterAll(["a.desktop"]), [true]);

// 4. Model invalidation (RootModel::refreshed -> invalidateFilter) with data
//    changes in between: removals and additions must re-dedupe correctly.
expect("refresh: app removed", filterAll(["a.desktop", "c.desktop"]), [true, true]);
expect("refresh: duplicate added again", filterAll(["c.desktop", "c.desktop", "a.desktop"]), [true, false, true]);

// 5. Rows without a favorite id are never filtered out.
expect("empty ids pass", filterAll(["", "a.desktop", "", "a.desktop"]), [true, true, true, false]);

// 6. Without the favoriteId role the proxy is a pass-through.
{
    dedupeProxy.favRole = -1;
    expect("no favRole: everything passes", filterAll(["x.desktop", "x.desktop"]), [true, true]);
    dedupeProxy.favRole = FAV_ROLE;
}

if (failures > 0) {
    console.error(`FAILED: ${failures} case(s)`);
    process.exit(1);
}
console.log("ALL CHECKS PASSED");
