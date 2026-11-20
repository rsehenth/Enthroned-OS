/*
 * Enthroned Settings - local history log (F3.9).
 * Appends JSON lines with facts about user-initiated operations to
 * $XDG_STATE_HOME/enthroned-os/settings-history.jsonl. No tokens, no
 * credentials, no personal paths are recorded - only timestamps, sources and
 * outcomes. Journal/flatpak-derived history stays in its original sources.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QVariantList>

namespace Enthroned {

class HistoryLog : public QObject
{
    Q_OBJECT
public:
    explicit HistoryLog(QObject* parent = nullptr);

    // Append one entry: {"ts": <ms>, "source": ..., "kind": ..., "title": ..., "detail": ...}
    void append(const QString& source, const QString& kind,
                const QString& title, const QString& detail);

    // Load recent own entries (newest last).
    Q_INVOKABLE QVariantList readRecent(int maxEntries) const;

private:
    QString logPath() const;
};

} // namespace Enthroned
