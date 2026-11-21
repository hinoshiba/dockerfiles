#!/bin/bash
# Run inside the Node image with EXPECTED_NODE from version/node/strict.
set -euo pipefail

for command in node nodejs npm npx corepack yarn yarnpkg bash git curl wget vim; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

test "$(node --version)" = "v${EXPECTED_NODE}"
test "$(nodejs --version)" = "v${EXPECTED_NODE}"
test "$(yarn --version)" = '1.22.22'
test "$(yarnpkg --version)" = '1.22.22'
npm --version
npx --version
corepack --version
node <<'JS'
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
assert.equal(JSON.parse('{"ok":true}').ok, true);
assert.equal(crypto.createHash('sha256').update('node').digest('hex').length, 64);
assert.equal(new URL('https://example.com/').protocol, 'https:');
JS
locale -a | grep -iq '^ja_JP\.utf8$'
test -d /usr/local/include/node
test -w /tmphome
echo 'Node image command compatibility checks passed.'
