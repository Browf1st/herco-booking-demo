import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { effectivePowderSize, wheelRate } from '../src/lib/shared/powderPricing.ts';

const read = (path) => readFile(new URL('../' + path, import.meta.url), 'utf8');
const row = (size) => ({ '10-14': size === '10-14' ? 100 : null, '17': size === '17' ? 200 : null, 'big-bike': size === 'big-bike' ? 300 : null, 'not-sure': null });
const model = {
	categories: ['standard'],
	baseTable: { standard: { '10-14': 1000, '17': 2000, 'big-bike': 3000, 'not-sure': null } },
	colorEntries: [{ id: 'red', name: 'Red', category: 'standard', photoPath: null, quoteOnly: false }],
	exceptions: [],
	bikeTiers: { 'big one': 'big-bike' }
};

test('a tiered bike is priced at its tier, matching the category hint, swatch and estimate', () => {
	assert.equal(effectivePowderSize(model, ' Big One ', '10-14'), 'big-bike');
	assert.equal(effectivePowderSize(model, 'Raider', '17'), '17');
	assert.equal(effectivePowderSize(model, 'Raider', ''), '');
	assert.equal(wheelRate(model, { bike: 'Big One', size: '10-14', finish: 'Red' }), 3000);
	assert.equal(wheelRate(model, { bike: 'Raider', size: '10-14', finish: 'Red' }), 1000);
});

test('the category From price uses the same effective size as the estimate', async () => {
	const choice = await read('src/lib/live/PowderChoice.svelte');
	assert.match(choice, /priceSize = \$derived\(effectivePowderSize\(model, bike, size\)\)/);
	assert.match(choice, /model\.baseTable\[next\]\?\.\[priceSize\]/);
	assert.match(choice, /The shop prices your bike at/);
});

test('top-right Edit price and Edit service hide when there is nothing to edit', async () => {
	const popup = await read('src/lib/live/ServerBookingPopup.svelte');
	assert.match(popup, /canEditPrice = \$derived\(canEditLines && rights\.price && showMoney && Boolean\(current\.current_services\?\.some\(line => expectedCentavos\(line\) !== undefined\)\)\)/);
	assert.match(popup, /onEditPrice=\{canEditPrice \?/);
	assert.match(popup, /onEditService=\{canEditLines && servicesEditable \?/);
	const edits = await read('src/lib/live/ServerServiceEdits.svelte');
	assert.match(edits, /servicesEditable = rights\.services && canEditServices && catalogLoaded/);
});

test('the Edit services dialog cannot be closed with Esc while saving', async () => {
	const dialog = await read('src/lib/shared/ServiceChangeDialog.svelte');
	assert.match(dialog, /oncancel=\{\(event\) => \{ if \(busy\) event\.preventDefault\(\); \}\}/);
});

test('the Actions menu never lets a late history.back() pop the details sheet or another menu', async () => {
	const menu = await read('src/lib/live/BookingActionsMenu.svelte');
	assert.match(menu, /hide\(false, true\)/);
	assert.match(menu, /if \(page\.state\.actionsMenu\) replaceState\('', \{ actionsMenu: id \}\)/);
	assert.match(menu, /!keepEntry && page\.state\.actionsMenu === id\) history\.back\(\)/);
	const sheet = await read('src/lib/shared/DetailsSheet.svelte');
	assert.match(sheet, /if \(page\.state\.actionsMenu\) replaceState\('', \{ detailsSheet: true \}\)/);
});

test('withdrawing a request asks first, and the change log says when it is capped', async () => {
	assert.match(await read('src/lib/live/ServerBookingHistory.svelte'), /confirm\('Withdraw this request\?/);
	assert.match(await read('src/lib/live/CustomerChangeLog.svelte'), /showAll && lines\.length >= historyCap/);
});

test('the slot filter closes on Esc and on a tap outside', async () => {
	const screen = await read('src/lib/live/ServerStaffBookings.svelte');
	assert.match(screen, /filterMenu\?\.open && event\.key === 'Escape'/);
	assert.match(screen, /!filterMenu\.contains\(event\.target as Node\)\) filterMenu\.open = false/);
});
