.pragma library

/*
 * Enthroned Launcher - desktop-shortcut command builder (Lote 9.2, H4-002).
 * Single source of truth shared by AppActions.qml and the Node regression
 * tests (scripts/test-launcher-appactions.mjs): the helper command is built
 * ONLY from a validated storage id, and the id never reaches the shell as
 * anything but a single-quoted argument. The helper re-validates on its side
 * (defense in depth).
 *
 * SPDX-License-Identifier: Apache-2.0
 */

var helper = "enthroned-desktop-shortcut";

// XDG desktop-file names are letters, digits and [._-]. Anything else
// (separators, whitespace, quotes, metacharacters) is not a storage id and
// must never reach the shell; "a..b" is rejected so no traversal can hide
// inside the name. Not trusting endsWith(".desktop") alone (H4-002).
function isValidStorageId(id) {
    return typeof id === "string"
        && /^[A-Za-z0-9][A-Za-z0-9._-]*\.desktop$/.test(id)
        && id.indexOf("..") === -1;
}

// POSIX single-quote escaping: the id stays ONE argument even if a future
// allowlist change ever lets a quoting character through.
function shellQuote(text) {
    return "'" + String(text).split("'").join("'\\''") + "'";
}

function buildCommand(id) {
    if (!isValidStorageId(id)) {
        return "";
    }
    return helper + " " + shellQuote(id);
}

// H4-011: at most one helper source connected at a time. The previous source
// is disconnected before a new one connects, so "create, remove, create
// again" in the same popup really runs the helper again (connectSource on an
// already-connected source is ignored by the DataSource engine).
function request(runner, previousCommand, id) {
    if (previousCommand) {
        runner.disconnectSource(previousCommand);
    }
    const command = buildCommand(id);
    if (!command) {
        return "";
    }
    runner.connectSource(command);
    return command;
}

// H4-011: consume the result (success or failure) and disconnect the source
// so the helper can run again later in the same session.
function consume(runner, activeCommand, source) {
    if (activeCommand && source === activeCommand) {
        runner.disconnectSource(source);
        return "";
    }
    return activeCommand;
}
