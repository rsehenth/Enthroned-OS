// Enthroned OS override for org.kde.plasmasetup.prepare.
// Upstream Aurora patched PrepareUtil to apply dev.getaurora.aurora*.desktop;
// skipping this page preserves Enthroned Classic on first login and lets the
// user pick Classic or Modern cleanly in Enthroned Welcome right after login.
//
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasmasetup.components as PlasmaSetupComponents

PlasmaSetupComponents.SetupModule {
    id: root
    available: false
    nextEnabled: true
}
