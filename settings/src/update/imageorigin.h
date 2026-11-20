/*
 * Enthroned Settings - bootc image origin policy (Lote 4).
 * Pure function, no I/O: classifies the booted image reference so the update
 * engine never offers a mutating update on an image that is not the Enthroned
 * channel. The application never runs `bootc switch/rebase`; this only guards
 * the existing uupd path (which upgrades from the current origin).
 *
 *   enthroned  - repository listed in release-channel.json
 *                (expected_image_references)
 *   unverified - no expected reference declared yet (dev channel) and not a
 *                generic Fedora/CentOS image; update allowed by this policy
 *   foreign    - generic Fedora/CentOS image, or not in the declared list
 *   unknown    - bootc status unavailable / empty reference
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QString>
#include <QStringList>

namespace Enthroned::ImageOrigin {

// "docker://Quay.io/x/y:tag@sha256:..." -> "quay.io/x/y"
inline QString repository(const QString& reference)
{
    QString ref = reference.trimmed().toLower();
    if (ref.startsWith(QLatin1String("docker://"))) {
        ref.remove(0, 9);
    }
    const qsizetype at = ref.indexOf(QLatin1Char('@'));
    if (at >= 0) {
        ref.truncate(at);
    }
    // A ':' after the last '/' is a tag; before it, a registry port.
    const qsizetype colon = ref.lastIndexOf(QLatin1Char(':'));
    if (colon > ref.lastIndexOf(QLatin1Char('/'))) {
        ref.truncate(colon);
    }
    return ref;
}

inline QString classify(const QString& bootedImage, const QStringList& expected)
{
    static const QStringList genericPrefixes = {
        QStringLiteral("quay.io/fedora/"),
        QStringLiteral("quay.io/fedora-ostree-desktops/"),
        QStringLiteral("registry.fedoraproject.org/"),
        QStringLiteral("quay.io/centos-bootc/"),
        QStringLiteral("quay.io/centos/"),
    };
    const QString repo = repository(bootedImage);
    if (repo.isEmpty()) {
        return QStringLiteral("unknown");
    }
    for (const QString& prefix : genericPrefixes) {
        if (repo.startsWith(prefix)) {
            return QStringLiteral("foreign");
        }
    }
    if (expected.isEmpty()) {
        return QStringLiteral("unverified");
    }
    for (const QString& entry : expected) {
        if (!entry.trimmed().isEmpty() && repository(entry) == repo) {
            return QStringLiteral("enthroned");
        }
    }
    return QStringLiteral("foreign");
}

inline bool allowsUpdate(const QString& origin)
{
    return origin == QLatin1String("enthroned") || origin == QLatin1String("unverified");
}

} // namespace Enthroned::ImageOrigin
