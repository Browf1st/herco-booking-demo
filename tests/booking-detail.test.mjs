import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { popupTotalCentavos } from '../src/lib/shared/report-ui.ts';

test('completed bookings show the final price; open bookings the current total', () => {
	assert.equal(popupTotalCentavos('done', 250000, 230000), 250000);
	assert.equal(popupTotalCentavos('done', null, 230000), 230000);
	assert.equal(popupTotalCentavos('confirmed', null, 230000), 230000);
	assert.equal(popupTotalCentavos('pending', 999, 230000), 230000);
	assert.equal(popupTotalCentavos('cancelled', null, null), undefined);
});

test('the popup hides every amount without income permission', async () => {
	const source = await readFile(new URL('../src/lib/live/booking-detail.ts', import.meta.url), 'utf8');
	assert.match(source, /price: showMoney \? money\(line\.price_centavos\) : undefined/);
	assert.match(source, /total: showMoney \? optionalMoney\(popupTotalCentavos/);
});
