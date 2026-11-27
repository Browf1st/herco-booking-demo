import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const route = await readFile(new URL('../src/routes/api/pricing/color-photo/+server.ts', import.meta.url), 'utf8');
const put = route.slice(route.indexOf('export const PUT'));
const get = route.slice(route.indexOf('export const GET'), route.indexOf('export const PUT'));

test('colour photo: only the public swatch bucket is used, never the private completion bucket', () => {
	assert.match(route, /const bucket = 'herco-swatches'/);
	assert.doesNotMatch(route.replace(/\/\/.*$/gm, ''), /herco-completion/);
});

test('colour photo PUT: same-origin, uuid entry, swatch RPC, upsert, 4 MB cap', () => {
	assert.ok(put.indexOf('requireSameOrigin(event)') > 0 && put.indexOf('requireSameOrigin(event)') < put.indexOf('entryId(event.url)'));
	assert.match(route, /const uuid = \/\^\[0-9a-f\]\{8\}/);
	assert.match(put, /herco_pricing_swatch_target/);
	assert.match(put, /'42501'\) error\(403/);
	assert.match(put, /'22023'\) error\(400, 'Save the colour before adding a photo\.'/);
	assert.match(put, /upsert: true/);
	assert.match(put, /status: 201/);
	assert.match(route, /4 \* 1024 \* 1024/);
	assert.match(route, /error\(413/);
	assert.match(route, /error\(400, 'Choose a JPEG, PNG, or WebP photo\.'\)/);
});

test('colour photo GET: public, nosniff, short public cache, fixed entry folder, 404 when missing', () => {
	assert.doesNotMatch(get, /requireSameOrigin|requestSupabase/);
	assert.match(get, /x-content-type-options': 'nosniff'/);
	assert.match(get, /cache-control': 'public, max-age=300'/);
	assert.match(get, /storage\.list\('entry'/);
	assert.match(get, /download\('entry\/'/);
	assert.match(get, /error\(404/);
});
