// Run with node --test scripts/test-profile-context-menu.mjs.
// SPDX-License-Identifier: Apache-2.0
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const right = 'RightButton;NoModifier';
const middle = 'MiddleButton;NoModifier';

for (const profile of ['classic', 'modern']) {
    test(`${profile} seeds the desktop binding after resetting the layout`, () => {
        const url = new URL(`../system_files/usr/share/plasma/look-and-feel/org.enthroned.${profile}/contents/layouts/org.kde.plasma.desktop-prelayout.js`, import.meta.url);
        const script = readFileSync(url, 'utf8');

        function run(installedPath, existingBindings) {
            const bindings = { ...existingBindings };
            function ConfigFile(parent, group) {
                if (typeof parent === 'string') {
                    assert.equal(parent, 'plasma-org.kde.plasma.desktop-appletsrc');
                    assert.equal(group, 'ActionPlugins');
                    this.groupList = existingBindings === undefined ? [] : ['0'];
                } else {
                    assert.equal(group, '0');
                    this.writeEntry = (key, value) => { bindings[key] = value; };
                }
            }
            runInNewContext(script, { ConfigFile, fileExists: path => path === installedPath });
            return bindings;
        }

        const module = '/qt6/plugins/plasma/containmentactions/org.enthroned.contextmenu.so';
        const expected = { [right]: 'org.enthroned.contextmenu', [middle]: 'org.kde.paste' };
        assert.deepEqual(run('/usr/lib64' + module), expected);
        assert.deepEqual(run('/usr/lib' + module), expected);
        assert.deepEqual(run(undefined), {});
        for (const bindings of [{ [right]: '' }, { [right]: 'org.kde.contextmenu' }, { [middle]: 'org.kde.paste' }]) {
            assert.deepEqual(run('/usr/lib64' + module, bindings), bindings);
        }
    });
}
