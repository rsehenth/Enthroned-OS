.pragma library

/*
 * Enthroned Settings - local settings search (Lote 4).
 * Pure functions over an in-memory list of entries; no index files, no
 * services. Matching is accent- and case-insensitive; every query word must
 * match (title, page, keywords/synonyms). Entry: { title, page, pageTitle,
 * keywords, module?, ... }. Unit-tested by settings/tests/run-tests.mjs.
 * SPDX-License-Identifier: Apache-2.0
 */

var ACCENTS = {
    "á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a",
    "é": "e", "è": "e", "ê": "e", "ë": "e",
    "í": "i", "ì": "i", "î": "i", "ï": "i",
    "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
    "ú": "u", "ù": "u", "û": "u", "ü": "u",
    "ç": "c", "ñ": "n"
};

function normalize(text) {
    var lower = String(text === undefined || text === null ? "" : text).toLowerCase();
    var out = "";
    for (var i = 0; i < lower.length; i++) {
        var ch = lower.charAt(i);
        out += ACCENTS[ch] !== undefined ? ACCENTS[ch] : ch;
    }
    // "wi-fi" and "wi fi" should find "wifi" and vice versa.
    return out.replace(/[-_.\/]+/g, " ");
}

function tokens(query) {
    var norm = normalize(query).replace(/\s+/g, " ").trim();
    return norm.length === 0 ? [] : norm.split(" ");
}

function squash(text) {
    return normalize(text).replace(/\s+/g, "");
}

// Score of one entry for the query tokens; 0 = no match.
function score(entry, queryTokens) {
    if (queryTokens.length === 0) {
        return 0;
    }
    var title = normalize(entry.title);
    var titleSquashed = squash(entry.title);
    var page = normalize(entry.pageTitle || "");
    var words = normalize(entry.keywords || "");
    var wordsSquashed = squash(entry.keywords || "");
    var total = 0;
    for (var i = 0; i < queryTokens.length; i++) {
        var token = queryTokens[i];
        var best = 0;
        if (title.indexOf(token) === 0) {
            best = 100;
        } else if (title.indexOf(" " + token) !== -1) {
            best = 80;
        } else if (title.indexOf(token) !== -1 || titleSquashed.indexOf(token) !== -1) {
            best = 60;
        } else if ((" " + words).indexOf(" " + token) !== -1) {
            best = 40;
        } else if (words.indexOf(token) !== -1 || wordsSquashed.indexOf(token) !== -1) {
            best = 30;
        } else if (page.indexOf(token) !== -1) {
            best = 15;
        }
        if (best === 0) {
            return 0;
        }
        total += best;
    }
    // An exact title match outranks pages whose longer title merely starts with it.
    if (title === queryTokens.join(" ")) {
        total += 50;
    }
    return total;
}

// Entries sorted by score (stable for ties: original order), at most `limit`.
function run(entries, query, limit) {
    var queryTokens = tokens(query);
    if (queryTokens.length === 0) {
        return [];
    }
    var scored = [];
    for (var i = 0; i < entries.length; i++) {
        var value = score(entries[i], queryTokens);
        if (value > 0) {
            scored.push({ entry: entries[i], score: value, order: i });
        }
    }
    scored.sort(function (a, b) {
        return b.score !== a.score ? b.score - a.score : a.order - b.order;
    });
    var max = limit > 0 ? limit : 30;
    var result = [];
    for (var j = 0; j < scored.length && j < max; j++) {
        result.push(scored[j].entry);
    }
    return result;
}
