'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');
const { parse } = require('jsonc-parser');
const { applySettings } = require('./apply-settings.cjs');

function readSettings(text) {
  const errors = [];
  const settings = parse(text, errors, { allowTrailingComma: true });
  assert.deepEqual(errors, []);
  return settings;
}

test('selective deep merge preserves personal preferences, comments, URLs and language overrides', () => {
  const live = `{
  // Old interpreter override
  "python.pythonPath": "/old/python",
  // Keep this comment about my theme
  "workbench.colorTheme": "My personal theme",
  "custom.url": "https://example.com/docs//section",
  "files.exclude": {
    // Keep personal nested comment
    "**/private-build": true,
    "**/__pycache__": false,
  },
  "[python]": {
    "editor.tabSize": 2,
    "editor.codeActionsOnSave": {
      // Keep nested code action
      "source.organizeImports": "explicit",
    },
  },
  "editor.rulers": [72, 100],
}
`;
  const patch = `{
  // Repository comments are accepted too
  "files.exclude": {"**/__pycache__": true},
  "[python]": {
    "editor.defaultFormatter": "ms-python.black-formatter",
    "editor.codeActionsOnSave": {"source.fixAll": "explicit"},
  },
  "editor.rulers": [80, 120],
}`;
  const removed = '["python.pythonPath", "already.absent"]';
  const result = applySettings(live, patch, removed);
  const settings = readSettings(result);
  assert.equal(settings['workbench.colorTheme'], 'My personal theme');
  assert.equal(settings['custom.url'], 'https://example.com/docs//section');
  assert.deepEqual(settings['files.exclude'], { '**/private-build': true, '**/__pycache__': true });
  assert.equal(settings['[python]']['editor.tabSize'], 2);
  assert.deepEqual(settings['[python]']['editor.codeActionsOnSave'], {
    'source.organizeImports': 'explicit', 'source.fixAll': 'explicit',
  });
  assert.equal(settings['[python]']['editor.defaultFormatter'], 'ms-python.black-formatter');
  assert.deepEqual(settings['editor.rulers'], [80, 120]);
  assert.equal(Object.hasOwn(settings, 'python.pythonPath'), false);
  for (const comment of ['Keep this comment about my theme', 'Keep personal nested comment', 'Keep nested code action']) {
    assert.ok(result.includes(`// ${comment}`));
  }
  assert.ok(result.includes('"custom.url": "https://example.com/docs//section",'));
  assert.equal(applySettings(result, patch, removed), result);
});

test('semantic no-op preserves exact bytes, CRLF, formatting and trailing commas', () => {
  const live = '{\r\n\t// personal formatting\r\n\t"group": { "second": 2, "first": 1, },\r\n}\r\n';
  assert.equal(applySettings(live, '{"group":{"first":1,"second":2}}', '["missing"]'), live);
  const changed = applySettings(live, '{"group":{"third":3}}', '[]');
  assert.ok(!/(?<!\r)\n/.test(changed));
  assert.ok(changed.includes('// personal formatting'));
  assert.equal(applySettings(changed, '{"group":{"third":3}}', '[]'), changed);
});

test('arrays replace; false and null remain explicit values; removals win over patch', () => {
  const result = applySettings(
    '{"array":[1,2],"value":{"old":true},"flag":true,"legacy":1}',
    '{"array":[3],"value":null,"flag":false,"new":{"nested":[4]},"legacy":2}',
    '["legacy"]',
  );
  assert.deepEqual(readSettings(result), { array: [3], value: null, flag: false, new: { nested: [4] } });
});

test('removing first, last and only properties preserves adjacent comments', () => {
  for (const live of [
    '{"legacy":1, /* my preference */ "keep":2}',
    '{"keep":2, /* my preference */ "legacy":1,}',
    '{/* my preference */ "legacy":1,}',
  ]) {
    const result = applySettings(live, '{}', '["legacy"]');
    assert.ok(result.includes('/* my preference */'));
    assert.equal(Object.hasOwn(readSettings(result), 'legacy'), false);
    assert.equal(applySettings(result, '{}', '["legacy"]'), result);
  }
});

test('comments inside removed legacy arrays and objects survive as standalone comments', () => {
  const live = `{
  "python.linting.pylintArgs": [
    "--old-option", // Keep the reason this option was set.
    /* Keep this block comment too. */
  ],
  "legacy.object": {"value": "https://example.invalid//not-a-comment" /* Inner explanation. */},
  "keep": true,
}\n`;
  const removed = '["python.linting.pylintArgs", "legacy.object"]';
  const result = applySettings(live, '{}', removed);
  assert.deepEqual(readSettings(result), { keep: true });
  for (const comment of [
    '// Keep the reason this option was set.',
    '/* Keep this block comment too. */',
    '/* Inner explanation. */',
  ]) assert.ok(result.includes(comment));
  assert.equal(result.includes('not-a-comment'), false);
  assert.equal(applySettings(result, '{}', removed), result);
});

test('ambiguous, malformed or incorrectly shaped sources fail', () => {
  for (const invalid of ['{"bad":', '{"a":1 "b":2}', '{"url":"https://unfinished}', '{"a":1,"a":2}', '{"a":{"b":1,"b":2}}']) {
    assert.throws(() => applySettings(invalid, '{}', '[]'));
    assert.throws(() => applySettings('{}', invalid, '[]'));
  }
  for (const nonObject of ['[]', 'null', '1', '"text"', '']) {
    assert.throws(() => applySettings(nonObject, '{}', '[]'));
    assert.throws(() => applySettings('{}', nonObject, '[]'));
  }
  for (const invalid of ['{}', '[1]', '[null]', 'not JSON']) {
    assert.throws(() => applySettings('{}', '{}', invalid));
  }
});

test('CLI emits only merged JSONC, leaves sources unchanged, and supports a missing destination', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vscode-settings-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const paths = ['live.json', 'patch.json', 'removed.json'].map(name => path.join(dir, name));
  const originals = ['{\n// personal\n"keep":1,"legacy":2,\n}\n', '{"added":true}', '["legacy"]'];
  paths.forEach((file, index) => fs.writeFileSync(file, originals[index]));
  const cli = path.join(__dirname, 'apply-settings.cjs');
  const result = spawnSync(process.execPath, [cli, ...paths], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.deepEqual(readSettings(result.stdout), { keep: 1, added: true });
  assert.ok(result.stdout.includes('// personal'));
  paths.forEach((file, index) => assert.equal(fs.readFileSync(file, 'utf8'), originals[index]));

  const missing = path.join(dir, 'missing-settings.json');
  const initial = spawnSync(process.execPath, [cli, missing, paths[1], paths[2]], { encoding: 'utf8' });
  assert.equal(initial.status, 0, initial.stderr);
  assert.deepEqual(readSettings(initial.stdout), { added: true });
  assert.equal(fs.existsSync(missing), false);

  fs.writeFileSync(paths[0], '{bad');
  const invalid = spawnSync(process.execPath, [cli, ...paths], { encoding: 'utf8' });
  assert.notEqual(invalid.status, 0);
  assert.equal(invalid.stdout, '');
  assert.match(invalid.stderr, /invalid JSONC/);
  assert.equal(fs.readFileSync(paths[0], 'utf8'), '{bad');
});
