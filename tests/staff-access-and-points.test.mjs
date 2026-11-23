import assert from 'node:assert/strict';
import test from 'node:test';
import { visibleActions } from '../src/lib/live/staff-access-actions.ts';
import { rankMap, sortMembers } from '../src/lib/live/points-ranking.ts';
import { pageCount } from '../src/lib/shared/paging.ts';

// Owner item 18 (2026-11-23): Activity log shows 10 entries per page.
test('page count for the 10-per-page Activity log', () => {
	assert.equal(pageCount(0, 10), 1, 'empty list still shows page 1');
	assert.equal(pageCount(1, 10), 1);
	assert.equal(pageCount(10, 10), 1);
	assert.equal(pageCount(11, 10), 2);
	assert.equal(pageCount(100, 10), 10, 'the server sends at most 100 entries');
	for (const bad of [-5, Number.NaN, Number.POSITIVE_INFINITY]) assert.equal(pageCount(bad, 10), 1, String(bad));
	assert.equal(pageCount(50, 0), 1);
});

// Owner item 13 (2026-11-23): the Staff Access form crashed when one action belonged to two ticked pages.
const catalog = [
	{ page: 'Booking history', key: 'completeBooking', label: 'Complete bookings and attach photos' },
	{ page: 'Bookings', key: 'confirmBooking', label: 'Confirm bookings' },
	{ page: 'Bookings', key: 'completeBooking', label: 'Complete bookings and attach photos' },
	{ page: 'Reports', key: 'viewIncome', label: 'View completed service value and final prices' }
];

test('regression: an action shared by two ticked pages is listed once', () => {
	const shown = visibleActions(catalog, ['Bookings', 'Booking history']);
	assert.deepEqual(shown.map((action) => action.key), ['completeBooking', 'confirmBooking']);
	assert.equal(new Set(shown.map((action) => action.key)).size, shown.length, 'keys must be unique for the keyed list');
});

test('actions follow the ticked pages', () => {
	assert.deepEqual(visibleActions(catalog, ['Bookings']).map((action) => action.key), ['confirmBooking', 'completeBooking']);
	assert.deepEqual(visibleActions(catalog, ['Booking history']).map((action) => action.key), ['completeBooking']);
	assert.deepEqual(visibleActions(catalog, []), []);
	assert.deepEqual(visibleActions([], ['Bookings']), []);
	assert.deepEqual(visibleActions(catalog, ['Unknown page']), []);
});

// Owner item 11 (2026-11-23): the # number is the real points rank in every sort and search.
const fans = [
	{ id: 'a', name: 'Ana Test', balance: 900 },
	{ id: 'b', name: 'Ben Test', balance: 500 },
	{ id: 'c', name: 'Cora Test', balance: 500 },
	{ id: 'd', name: 'Dan Test', balance: 0 }
];

test('rank comes from the server order (highest points first)', () => {
	const ranks = rankMap(fans);
	assert.deepEqual([...ranks], [['a', 1], ['b', 2], ['c', 3], ['d', 4]]);
	assert.equal(rankMap([]).size, 0);
});

test('regression: sorting by name or fewest points keeps each fan\'s own rank', () => {
	const ranks = rankMap(fans);
	const byName = sortMembers([...fans].reverse(), 'name', ranks);
	assert.deepEqual(byName.map((fan) => fan.id), ['a', 'b', 'c', 'd']);
	const lowest = sortMembers(fans, 'lowest', ranks);
	assert.deepEqual(lowest.map((fan) => [fan.id, ranks.get(fan.id)]), [['d', 4], ['c', 3], ['b', 2], ['a', 1]]);
	const highest = sortMembers([...fans].reverse(), 'points', ranks);
	assert.deepEqual(highest.map((fan) => fan.id), ['a', 'b', 'c', 'd'], 'ties keep rank order');
});

test('a searched fan keeps the rank from the full list; unknown fans sort last', () => {
	const ranks = rankMap(fans);
	const searched = sortMembers([fans[2]], 'points', ranks);
	assert.equal(ranks.get(searched[0].id), 3);
	const outsider = { id: 'z', name: 'Zed Test', balance: 500 };
	assert.deepEqual(sortMembers([outsider, fans[1]], 'points', ranks).map((fan) => fan.id), ['b', 'z']);
	assert.equal(ranks.get('z'), undefined);
});
