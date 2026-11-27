import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { ceramicAddons } from '../src/lib/shared/bookingCatalog.ts';
import { catalogRate } from '../src/lib/live/ui-catalog.ts';
import { cleanPowderModel, newException, powderModelProblem } from '../src/lib/live/powder-model.ts';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const baseModel = () => ({ categories: [], baseTable: {}, colorEntries: [], exceptions: [], bikeTiers: {} });

test('add-ons are real checkboxes bound to the selection array', async () => {
	const cards = await read('../src/lib/live/CeramicAddonCards.svelte');
	assert.match(cards, /type="checkbox"[^>]*bind:group=\{selected\}/);
	assert.match(cards, /:has\(:focus-visible\)/);
	const screen = await read('../src/lib/live/ServerBookingCatalog.svelte');
	assert.match(screen, /bind:selected=\{options\.ceramicAddons\}/);
	assert.ok(Object.keys(ceramicAddons).length > 1);
});

test('warranty copy appears once, green, and turnover line is the agreed wording', async () => {
	const screen = await read('../src/lib/live/ServerBookingCatalog.svelte');
	assert.equal(screen.split('2–5 years').length - 1, 1);
	assert.match(screen, /hours turnover · wait at shop or pick up later/);
	assert.match(screen, /\.warranty \{[^}]*color: var\(--ok\)/);
	assert.doesNotMatch(screen, /Wait at the shop or pick up later/);
});

test('ceramic exception: no finish needed, finish cleared, own duplicate key', () => {
	const m = baseModel();
	m.exceptions = [{ ...newException(), service: 'ceramic', bikeKey: 'Honda PCX', finish: 'leftover', priceCentavos: 500000 }];
	assert.equal(powderModelProblem(m), '');
	assert.equal(cleanPowderModel(m).exceptions[0].finish, '');
	assert.equal(cleanPowderModel(m).exceptions[0].service, 'ceramic');
	m.exceptions.push({ ...newException(), service: 'ceramic', bikeKey: 'honda pcx ' });
	assert.match(powderModelProblem(m), /same finish/);
});

test('wheel colour exceptions still need a finish', () => {
	const m = baseModel();
	m.exceptions = [{ ...newException(), bikeKey: 'honda pcx' }];
	assert.match(powderModelProblem(m), /needs a finish/);
});

test('staff exceptions editor offers the Ceramic service', async () => {
	const editor = await read('../src/lib/live/PowderExceptions.svelte');
	assert.match(editor, /<option value="ceramic">Ceramic<\/option>/);
	assert.match(editor, /<option value="wheel-colour">Wheel colour<\/option>/);
});

test('a ceramic exception sets the on-screen ceramic price for that bike only', () => {
	const config = { ceramic: { tiers: { '1999': 1999 }, models: { 'Honda PCX': '1999' } }, powderModel: { ...baseModel(), exceptions: [{ ...newException(), service: 'ceramic', bikeKey: 'honda pcx', priceCentavos: 250000 }] } };
	const value = { catalog: { otherBigBike: false, bigBike: false, ceramicAddons: [] } };
	assert.deepEqual(catalogRate(config, value, 'Honda PCX', 2024, 'Ceramic coating'), [2500, 2500]);
	assert.deepEqual(catalogRate(config, value, 'Yamaha Aerox', 2024, 'Ceramic coating'), undefined);
	config.powderModel.exceptions[0].enabled = false;
	assert.deepEqual(catalogRate(config, value, 'Honda PCX', 2024, 'Ceramic coating'), [1999, 1999]);
	config.powderModel.exceptions[0].enabled = true; config.powderModel.exceptions[0].quoteOnly = true;
	assert.equal(catalogRate(config, value, 'Honda PCX', 2024, 'Ceramic coating'), undefined);
});
