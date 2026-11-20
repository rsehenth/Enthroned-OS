#!/usr/bin/env node
/*
 * Lote 11B - regression test for the launcher PINNED dedupe proxy (H4 P2:
 * "Brave" duplicated in the Fixados grid with two different ids).
 * Extracts the REAL pinned filterRowCallback from FullRepresentation.qml (no
 * copy, no text assertion) and executes it against a minimal
 * KSortFilterProxyModel harness. The canonical key is the kicker `url` role
 * (resolved .desktop file) with the favoriteId as fallback, so:
 *   - a preferred://browser alias row and a directly pinned
 *     applications:<id>.desktop row (same resolved file) keep ONE tile;
 *   - genuinely different desktop files (Flatpak vs. plain desktop entry)
 *     are never merged ("do not remove different favorites by mistake");
 *   - order is preserved (first occurrence wins) and nothing is written
 *     back to the favorites store.
 *
 * Run: node scripts/test-launcher-pinned-dedupe.mjs
 * SPDX-License-Identifier: Apache-2.0
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const qml = readFileSync(join(root,
    "system_files/usr/share/plasma/plasmoids/org.enthroned.launcher/contents/ui/FullRepresentation.qml"),
    "utf8");

// The pinned proxy is the SECOND filterRowCallback in the file; anchor the
// search on its id so refactors of the category proxy cannot false-positive.
const anchor = qml.indexOf("id: pinnedDedupe");
const marker = anchor < 0 ? -1 : qml.indexOf("filterRowCallback:", anchor);
if (marker < 0) {
    console.error("FAIL: pinnedDedupe filterRowCallback not found in FullRepresentation.qml");
    process.exit(1);
}
const bodyStart = qml.indexOf("{", qml.indexOf("=>", marker));
let depth = 0, bodyEnd = -1;
for (let i = bodyStart; i < qml.length; ++i) {
    if (qml[i] === "{") ++depth;
    else if (qml[i] === "}") { --depth; if (depth === 0) { bodyEnd = i; break; } }
}
if (bodyEnd < 0) {
    console.error("FAIL: could not extract pinned filterRowCallback");
    process.exit(1);
}
const arrowSource = qml.slice(qml.indexOf("(", marker), bodyEnd + 1);

const FAV_ROLE = 1;
const URL_ROLE = 2;
let currentModel = null;
const pinnedDedupe = {
    favRole: FAV_ROLE,
    urlRole: URL_ROLE,
    get sourceModel() { return currentModel; },
};
const predicate = new Function("pinnedDedupe", `return (${arrowSource});`)(pinnedDedupe);

function makeModel(rows) {
    // rows: [{ url, favId }] or bare strings (favId only).
    return {
        index(row) { return { row }; },
        data(index, role) {
            const entry = rows[index.row];
            if (entry === undefined) return null;
            if (role === URL_ROLE) {
                return (typeof entry === "object" ? entry.url : "") ?? "";
            }
            if (role === FAV_ROLE) {
                return (typeof entry === "object" ? entry.favId : entry) ?? "";
            }
            return null;
        },
    };
}

// Runs a full accept-row pass like KSortFilterProxyModel does.
function filterAll(rows) {
    currentModel = makeModel(rows);
    return rows.map((_, row) => predicate(row, undefined));
}

// The visible rows (first-occurrence survivors), to assert order preservation.
function visibleIds(rows) {
    const keep = filterAll(rows);
    return rows.filter((_, row) => keep[row])
        .map((entry) => (typeof entry === "object" ? entry.favId : entry));
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

const FLATPAK_URL = "file:///var/lib/flatpak/exports/share/applications/com.brave.Browser.desktop";

// 1. H4 audit reproduction: the preferred://browser alias row and the
//    directly pinned applications: row resolve to the SAME .desktop file
//    (identical url role) -> one tile, first occurrence kept.
expect("alias + pinned entry of the same app collapse",
    filterAll([
        { url: FLATPAK_URL, favId: "preferred://browser" },
        { url: FLATPAK_URL, favId: "applications:com.brave.Browser.desktop" },
        { url: "file:///usr/share/applications/org.kde.dolphin.desktop", favId: "applications:org.kde.dolphin.desktop" },
    ]),
    [true, false, true]);

// 2. Flatpak vs. desktop entry variants are DIFFERENT files: both stay
//    (task rule: do not remove different favorites by mistake).
expect("flatpak and desktop-entry variants are kept",
    filterAll([
        { url: FLATPAK_URL, favId: "applications:com.brave.Browser.desktop" },
        { url: "file:///usr/share/applications/brave-browser.desktop", favId: "applications:brave-browser.desktop" },
    ]),
    [true, true]);

// 3. Textual id alone is NOT the identity: two different ids with the same
//    resolved file collapse; two rows without urls fall back to favoriteId.
expect("different favoriteIds with different urls both stay",
    filterAll([
        { url: FLATPAK_URL, favId: "preferred://browser" },
        { url: "file:///usr/share/applications/brave-browser.desktop", favId: "applications:brave-browser.desktop" },
    ]),
    [true, true]);
expect("fallback: identical favoriteIds without url collapse",
    filterAll(["applications:app.desktop", "applications:app.desktop"]),
    [true, false]);

// 4. Rows without any key are never filtered out.
expect("empty keys pass",
    filterAll(["", "applications:a.desktop", "", "applications:a.desktop"]),
    [true, true, true, false]);
expect("empty url with empty favId passes",
    filterAll([{ url: "", favId: "" }, { url: "", favId: "" }]),
    [true, true]);

// 5. Order preservation: survivors keep the favorites order.
expect("order preserved",
    visibleIds([
        { url: "file:///a.desktop", favId: "applications:a.desktop" },
        { url: FLATPAK_URL, favId: "preferred://browser" },
        { url: "file:///b.desktop", favId: "applications:b.desktop" },
        { url: FLATPAK_URL, favId: "applications:com.brave.Browser.desktop" },
    ]),
    ["applications:a.desktop", "preferred://browser", "applications:b.desktop"]);

// 6. Re-evaluation is stable (pure predicate, no hidden state).
const audit = [
    { url: FLATPAK_URL, favId: "preferred://browser" },
    { url: FLATPAK_URL, favId: "applications:com.brave.Browser.desktop" },
];
filterAll(audit);
expect("re-evaluation is stable", filterAll(audit), [true, false]);

// 7. Favorites change between passes (unpin/re-pin): refresh re-dedupes.
expect("refresh: duplicate removed then re-added",
    filterAll([{ url: FLATPAK_URL, favId: "preferred://browser" }])
        .concat([]).length === 1
    && filterAll([
        { url: FLATPAK_URL, favId: "preferred://browser" },
        { url: FLATPAK_URL, favId: "applications:com.brave.Browser.desktop" },
        { url: FLATPAK_URL, favId: "preferred://browser" },
    ]).join(",") === [true, false, false].join(","),
    true);

// 8. Without the favoriteId role the proxy is a pass-through.
{
    pinnedDedupe.favRole = -1;
    expect("no favRole: everything passes", filterAll([{ url: FLATPAK_URL }, { url: FLATPAK_URL }]), [true, true]);
    pinnedDedupe.favRole = FAV_ROLE;
}

// 9. Document rows (file favorites) keep their distinct urls.
expect("document favorites never merged",
    filterAll([
        { url: "file:///home/u/relatorio.odt", favId: "file:///home/u/relatorio.odt" },
        { url: "file:///home/u/notas.txt", favId: "file:///home/u/notas.txt" },
    ]),
    [true, true]);

if (failures > 0) {
    console.error(`FAILED: ${failures} case(s)`);
    process.exit(1);
}
console.log("ALL CHECKS PASSED");
