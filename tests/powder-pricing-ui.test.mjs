import assert from 'node:assert/strict';
import test from 'node:test';
import { cleanPowderModel, normaliseKey, newColorEntry, newException, powderModelProblem } from '../src/lib/live/powder-model.ts';
import { powderSizeLabels, pricedPowderSizes } from '../src/lib/shared/bookingCatalog.ts';

const model = () => ({
	categories: ['basic', 'special', 'luminous-prismatic', 'custom'],
	baseTable: {}, colorEntries: [], exceptions: [], bikeTiers: {}
});

test('labels the 17 size as 15–17 in and never prices Not sure', () => {
	assert.equal(powderSizeLabels['17'], '15–17 in');
	assert.ok(!pricedPowderSizes.includes('not-sure'));
});

test('new colours start enabled and cleaning keeps the enabled flag', () => {
	assert.equal(newColorEntry().enabled, true);
	const m = model();
	m.colorEntries = [{ ...newColorEntry(), name: 'Off one', enabled: false }];
	assert.equal(cleanPowderModel(m).colorEntries[0].enabled, false);
});

test('new entries get unique ids and exceptions are wheel-colour', () => {
	assert.notEqual(newColorEntry().id, newColorEntry().id);
	assert.equal(newException().service, 'wheel-colour');
});

test('flags empty and duplicate colour names, ignoring case', () => {
	const m = model();
	m.colorEntries = [{ ...newColorEntry(), name: ' ' }];
	assert.match(powderModelProblem(m), /needs a name/);
	m.colorEntries = [{ ...newColorEntry(), name: 'Fire Blue' }, { ...newColorEntry(), name: 'fire blue ' }];
	assert.match(powderModelProblem(m), /different/);
});

test('flags duplicate exceptions and accepts distinct ones', () => {
	const m = model();
	const a = { ...newException(), bikeKey: 'Honda PCX', finish: 'Matte' };
	m.exceptions = [a, { ...newException(), bikeKey: 'honda pcx ', finish: 'matte' }];
	assert.match(powderModelProblem(m), /same finish/);
	m.exceptions = [a, { ...newException(), bikeKey: 'honda pcx', finish: 'matte', fromFinish: 'gloss' }];
	assert.equal(powderModelProblem(m), '');
});

test('cleaning lowercases bike keys, forces Custom to quote and drops empty prices', () => {
	const m = model();
	m.colorEntries = [
		{ ...newColorEntry(), name: ' Neon ', category: 'custom', quoteOnly: false, pricesBySize: { '17': 3000 } },
		{ ...newColorEntry(), name: 'Plain', pricesBySize: {} }
	];
	m.exceptions = [{ ...newException(), bikeKey: ' Honda PCX160 ', finish: ' Matte ', fromFinish: ' ', quoteOnly: true, priceCentavos: 5 }];
	m.bikeTiers = { ' Yamaha Mio ': '10-14' };
	const clean = cleanPowderModel(m);
	assert.deepEqual([clean.colorEntries[0].name, clean.colorEntries[0].quoteOnly, clean.colorEntries[0].pricesBySize], ['Neon', true, undefined]);
	assert.equal(clean.colorEntries[1].pricesBySize, undefined);
	assert.deepEqual([clean.exceptions[0].bikeKey, clean.exceptions[0].fromFinish, clean.exceptions[0].priceCentavos], ['honda pcx160', undefined, undefined]);
	assert.deepEqual(clean.bikeTiers, { 'yamaha mio': '10-14' });
	assert.equal(normaliseKey('  AbC '), 'abc');
});

test('the pricing screen no longer mounts the retired rule editor', async () => {
	const { readFile } = await import('node:fs/promises');
	const page = await readFile(new URL('../src/routes/pricing/+page.svelte', import.meta.url), 'utf8');
	assert.ok(!page.includes('CoatingRuleEditor'));
});
