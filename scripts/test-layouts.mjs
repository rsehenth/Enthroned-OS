// Run the shipped Plasma layouts with applet creation failures simulated.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

let checks = 0;
for (const profile of ['classic', 'modern']) {
  const source = readFileSync(new URL(`../system_files/usr/share/plasma/look-and-feel/org.enthroned.${profile}/contents/layouts/org.kde.plasma.desktop-layout.js`, import.meta.url), 'utf8');
  for (const failure of ['late-qml-error', 'missing', 'throws']) {
    const widgets = [];
    const context = {
      Panel: function () {
        return { addWidget(id) {
          if (id === 'org.enthroned.launcher') {
            if (failure === 'missing') return null;
            if (failure === 'throws') throw new Error('Missing applet');
            // Plasma can return an applet before its QML fails to load.
          }
          const widget = { id, config: {}, writeConfig(key, value) { this.config[key] = value; } };
          widgets.push(widget);
          return widget;
        } };
      },
      desktopsForActivity: () => [],
      currentActivity: () => 'test',
    };
    vm.runInNewContext(source, context);
    // Single visible Start button: Kickoff is added only when the launcher
    // cannot be created. A late QML failure leaves the launcher widget in the
    // panel (no second button); recovery is "Show alternatives" -> Kickoff.
    const starts = widgets.filter(widget => widget.id === 'org.enthroned.launcher' || widget.id === 'org.kde.plasma.kickoff');
    assert.equal(starts.length, 1, `${profile}/${failure}: exactly one Start menu widget`);
    const expected = failure === 'late-qml-error' ? 'org.enthroned.launcher' : 'org.kde.plasma.kickoff';
    assert.equal(starts[0].id, expected, `${profile}/${failure}: unexpected Start widget`);
    assert.equal(starts[0].config.global, 'Meta');
    // Lote 13: each profile owns its Start icon (Classic = E mark, Modern =
    // throne), on the custom launcher and on the stock fallback alike.
    assert.equal(starts[0].config.icon, `org.enthroned.launcher-${profile}`, `${profile}/${failure}: Start icon`);
    checks++;
  }
}
console.log(`Layout recovery: ${checks} scenarios passed (simulated Plasma API; real Plasma NOT RUN)`);
