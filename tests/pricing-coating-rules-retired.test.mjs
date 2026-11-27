import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');

test('coating-rules route is retired: both methods return 410 and call no dropped RPC', async () => {
	const src = await read('../src/routes/api/pricing/coating-rules/+server.ts');
	// Returns 410 for both GET and POST.
	assert.match(src, /status:\s*410/);
	assert.match(src, /export const GET/);
	assert.match(src, /export const POST/);
	// POST keeps the same-origin guard before replying.
	assert.match(src, /requireSameOrigin/);
	// The dropped RPCs are no longer referenced (migrated into powderModel.exceptions).
	assert.doesNotMatch(src, /herco_coating_rules|herco_save_coating_rule/);
});

test('api-contract marks coating-rules retired and points to the pricing catalog', async () => {
	const contract = await read('../docs/api-contract.md');
	assert.match(contract, /\/api\/pricing\/coating-rules/);
	assert.match(contract, /Retired in F-021/);
	assert.match(contract, /powderModel\.exceptions/);
});
