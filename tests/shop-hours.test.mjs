import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { toShopHours } from '../src/lib/server/shop-hours.ts';

test('shop hours keep only the three public fields', () => {
	const result = toShopHours({ openHour: 9, closeHour: 17, openWeekdays: [0, 3, 4, 5, 6], secret: 'x' });
	assert.deepEqual(result, { openHour: 9, closeHour: 17, openWeekdays: [0, 3, 4, 5, 6] });
});

test('shop hours sort and de-duplicate weekdays, and accept the widest day', () => {
	assert.deepEqual(toShopHours({ openHour: 0, closeHour: 24, openWeekdays: [6, 0, 6] }),
		{ openHour: 0, closeHour: 24, openWeekdays: [0, 6] });
});

test('shop hours reject answers that do not look right', () => {
	const ok = { openHour: 9, closeHour: 17, openWeekdays: [1] };
	for (const bad of [null, undefined, 'x', 5, [], {}, { ...ok, openHour: 24 }, { ...ok, openHour: -1 },
		{ ...ok, closeHour: 25 }, { ...ok, closeHour: 0 }, { ...ok, closeHour: 9 }, { ...ok, openHour: '9' },
		{ ...ok, openHour: 9.5 }, { ...ok, openWeekdays: [] }, { ...ok, openWeekdays: [7] }, { ...ok, openWeekdays: [-1] },
		{ ...ok, openWeekdays: ['1'] }, { ...ok, openWeekdays: 'Wed' }, { ...ok, openWeekdays: [0, 1, 2, 3, 4, 5, 6, 0] }]) {
		assert.equal(toShopHours(bad), null, JSON.stringify(bad));
	}
});

test('the route answers anyone with a short public cache and no sign-in check', async () => {
	const route = await readFile(new URL('../src/routes/api/shop-hours/+server.ts', import.meta.url), 'utf8');
	assert.match(route, /rpc\('herco_shop_hours'\)/);
	assert.match(route, /public, max-age=60/);
	assert.doesNotMatch(route, /requireSameOrigin|getUser|getSession/);
});
