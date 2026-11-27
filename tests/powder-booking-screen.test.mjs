import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { createCatalogOptions, catalogItems } from '../src/lib/shared/bookingCatalog.ts';
import { findColorEntry, powderSizeFromValue, wheelRate } from '../src/lib/shared/powderPricing.ts';
import { catalogRate, uiCoatingSnapshot } from '../src/lib/live/ui-catalog.ts';

const model = {
	categories: ['basic', 'special', 'luminous-prismatic', 'custom'],
	baseTable: {
		basic: { '10-14': 2199, '17': 3199, 'big-bike': 4499, 'not-sure': null },
		special: { '10-14': 2499, '17': 3499, 'big-bike': 5499, 'not-sure': null },
		'luminous-prismatic': { '10-14': 2999, '17': 3999, 'big-bike': 6999, 'not-sure': null },
		custom: { '10-14': null, '17': null, 'big-bike': null, 'not-sure': null }
	},
	colorEntries: [
		{ id: 'c1', name: 'Snow White', category: 'basic', photoPath: null, quoteOnly: false },
		{ id: 'c2', name: 'Fire Blue', category: 'special', photoPath: 'entry/c2.webp', quoteOnly: false, pricesBySize: { '10-14': 2699 } },
		{ id: 'c3', name: 'Aurora', category: 'luminous-prismatic', photoPath: null, quoteOnly: false },
		{ id: 'c4', name: 'Two-tone gold', category: 'custom', photoPath: null, quoteOnly: true }
	],
	exceptions: [
		{ id: 'x1', service: 'wheel-colour', bikeKey: 'honda pcx160', finish: 'Fire Blue', priceCentavos: 350000, quoteOnly: false, enabled: true, note: '' },
		{ id: 'x2', service: 'wheel-colour', bikeKey: 'honda click', finish: 'Snow White', quoteOnly: true, enabled: true, note: '' },
		{ id: 'x3', service: 'wheel-colour', bikeKey: 'honda beat', finish: 'Snow White', priceCentavos: 100, quoteOnly: false, enabled: false, note: '' }
	],
	bikeTiers: { 'yamaha nmax': 'big-bike' }
};
const rate = (input) => wheelRate(model, { bike: 'Yamaha Mio', size: '10-14', finish: 'Snow White', ...input });

test('prices every size and category from the base table', () => {
	assert.equal(rate({}), 2199);
	assert.equal(rate({ size: '17' }), 3199);
	assert.equal(rate({ size: 'big-bike' }), 4499);
	assert.equal(rate({ finish: 'Aurora', size: 'big-bike' }), 6999);
	assert.equal(rate({ finish: 'fire blue', size: '17' }), 3499);
});

test('a colour price for a size beats the category price', () => assert.equal(rate({ finish: 'Fire Blue' }), 2699));
test('an enabled exception beats everything and is read in centavos', () => {
	assert.equal(rate({ bike: 'Honda PCX160', finish: 'Fire Blue' }), 3500);
	assert.equal(rate({ bike: 'Honda Click', size: '17' }), undefined);
	assert.equal(rate({ bike: 'Honda Beat' }), 2199);
});
test('Custom, Not sure, no colour and unknown colours are quotes', () => {
	assert.equal(rate({ finish: 'Two-tone gold' }), undefined);
	assert.equal(rate({ size: 'not-sure' }), undefined);
	assert.equal(rate({ size: '' }), undefined);
	assert.equal(rate({ finish: '' }), undefined);
	assert.equal(rate({ finish: 'Mystery' }), undefined);
});
test('a bike listed in bikeTiers uses its tier like the server does', () => assert.equal(rate({ bike: 'Yamaha NMAX' }), 4499));
test('the old prismatic flag still raises the category', () => assert.equal(rate({ prismatic: true }), 2999));
test('finds a colour by id or by name and reads old size labels', () => {
	assert.equal(findColorEntry(model, 'C2')?.name, 'Fire Blue');
	assert.equal(findColorEntry(model, ' snow white ')?.id, 'c1');
	assert.equal(findColorEntry(model, 'nope'), undefined);
	assert.equal(powderSizeFromValue('17 inches (Raider / Sniper only)'), '17');
	assert.equal(powderSizeFromValue('10–14 inches'), '10-14');
	assert.equal(powderSizeFromValue('Big bike / sports bike'), 'big-bike');
	assert.equal(powderSizeFromValue('Not sure'), 'not-sure');
	assert.equal(powderSizeFromValue(undefined), '');
});

const selection = (patch = {}, finish = 'Snow White') => ({
	ceramic: false, powder: true, ceramicFinish: '', red: false, powderParts: ['Wheels / mags'], front: '', rear: '', finish,
	catalog: { ...createCatalogOptions(), wheelType: '17', ...patch }
});

test('any bike can price the 15–17 in size: no Raider or Sniper needed', () => {
	assert.deepEqual(catalogRate({ powderModel: model }, selection(), 'Honda Click125', undefined, 'Wheels / mags'), [3199, 3199]);
	const items = catalogItems(selection(), selection().catalog, 'Honda Click125', undefined, undefined, model);
	assert.deepEqual([...items.values()][0], [3199, 3199]);
	assert.ok([...items.keys()][0].includes('15–17 in'));
});
test('without a powder model the wheel line is a quote, never an old hard-coded price', () => {
	assert.equal(catalogRate({}, selection(), 'Yamaha Sniper 155', undefined, 'Wheels / mags'), undefined);
});

test('the snapshot carries category, colour id and a trimmed custom note only for Custom', () => {
	const custom = uiCoatingSnapshot(selection({ powderCategory: 'custom', colorId: 'c4', customNote: '  gold lips  ' }, 'Two-tone gold'));
	assert.deepEqual([custom.ui_catalog.powder_category, custom.ui_catalog.color_id, custom.ui_catalog.custom_note], ['custom', 'c4', 'gold lips']);
	const basic = uiCoatingSnapshot(selection({ powderCategory: 'basic', colorId: 'c1', customNote: 'left over' }));
	assert.equal(basic.ui_catalog.custom_note, undefined);
	assert.equal(basic.ui_catalog.wheel_type, '17');
	const long = uiCoatingSnapshot(selection({ powderCategory: 'custom', customNote: 'x'.repeat(500) }, ''));
	assert.equal(long.ui_catalog.custom_note.length, 300);
});
test('an old saved booking (prismatic flag, no category) still builds a snapshot', () => {
	const old = uiCoatingSnapshot(selection({ prismatic: true, wheelType: '17 inches (Raider / Sniper only)' }));
	assert.equal(old.ui_catalog.prismatic, true);
	assert.equal(old.ui_catalog.powder_category, undefined);
	assert.equal('raider_sniper_confirmed' in old.ui_catalog, false);
});
test('the Not sure size key the card saves is recognised (not treated as no size)', () => {
	assert.equal(powderSizeFromValue('not-sure'), 'not-sure');
	assert.equal(powderSizeFromValue('Not sure'), 'not-sure');
});
test('unticking Mags drops the wheel size/colour so the server does not refuse the booking', () => {
	const snap = uiCoatingSnapshot({ ...selection({ powderCategory: 'basic', colorId: 'c1' }), powderParts: ['Swingarm'] });
	assert.equal(snap.ui_catalog.wheel_type, '');
	assert.equal(snap.ui_catalog.finish, '');
	assert.equal(snap.ui_catalog.powder_category, undefined);
	assert.equal(snap.ui_catalog.color_id, undefined);
});

test('the Raider and Sniper restriction is gone from the screen code', async () => {
	for (const file of ['../src/lib/shared/coating.ts', '../src/lib/shared/bookingCatalog.ts', '../src/lib/live/ServerBookingCatalog.svelte', '../src/lib/live/PowderChoice.svelte']) {
		const text = await readFile(new URL(file, import.meta.url), 'utf8');
		assert.ok(!/Raider \/ Sniper only|Raider and Sniper only|wheelRates/.test(text), file);
	}
});
test('the booking screen shows colours for every size, including Not sure', async () => {
	const screen = await readFile(new URL('../src/lib/live/ServerBookingCatalog.svelte', import.meta.url), 'utf8');
	assert.match(screen, /hasMags \|\| showParts/);
	assert.match(screen, /<PowderChoice/);
	const choice = await readFile(new URL('../src/lib/live/PowderChoice.svelte', import.meta.url), 'utf8');
	assert.match(choice, /powderSizes/);
	assert.ok(!/size === 'not-sure'\s*\?\s*\[\]/.test(choice));
});
