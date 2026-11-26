import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { bookingWasUpdated, editRights, expectedCentavos, historyLine, parsePesos, parseReason } from '../src/lib/shared/booking-changes.ts';

// 2026-11-24 07:10 UTC = 3:10 PM in the Philippines.
const at = '2026-11-24T07:10:00Z';

test('parsePesos accepts whole pesos with a sign or commas', () => {
	for (const [text, pesos] of [['2300', 2300], [' ₱2,300 ', 2300], ['0', 0], ['1000000', 1_000_000], ['2300.00', 2300]]) {
		assert.deepEqual(parsePesos(text), { ok: true, pesos }, text);
	}
});

test('parsePesos refuses blank, negative, decimal, huge and odd input with a plain message', () => {
	assert.match(parsePesos('').message, /Enter the new price/);
	assert.match(parsePesos('   ').message, /Enter the new price/);
	assert.match(parsePesos('-5').message, /below ₱0/);
	assert.match(parsePesos('10.5').message, /whole pesos/);
	assert.match(parsePesos('1000001').message, /more than ₱1,000,000/);
	for (const text of ['abc', '12abc', '1e5', '--1', '.5', '<script>']) assert.equal(parsePesos(text).ok, false, text);
});

test('parseReason trims, requires text and caps the length at 200', () => {
	assert.deepEqual(parseReason('  Extra corrosion found  '), { ok: true, reason: 'Extra corrosion found' });
	assert.equal(parseReason('   ').ok, false);
	assert.equal(parseReason('x'.repeat(200)).ok, true);
	assert.equal(parseReason('x'.repeat(201)).ok, false);
});

test('historyLine shows time in Philippine time, who, the price change and the reason', () => {
	const line = historyLine({ at, kind: 'price_changed', actor: 'Elijah', service_label: 'Ceramic coating', from_centavos: 179900, to_centavos: 230000, reason: 'Extra corrosion found' });
	assert.equal(line, 'Nov 24, 3:10 PM · Elijah · Ceramic coating ₱1,799 → ₱2,300 · Extra corrosion found');
});

test('historyLine handles added, removed, corrected and status entries', () => {
	assert.match(historyLine({ at, kind: 'service_added', actor: 'Elijah', service_label: 'Helmet coating', to_centavos: 29900 }), /Elijah · Added Helmet coating ₱299$/);
	assert.match(historyLine({ at, kind: 'service_removed', actor: 'Elijah', service_label: 'Helmet coating', from_centavos: 29900 }), /Removed Helmet coating ₱299$/);
	assert.match(historyLine({ at, kind: 'price_corrected', actor: 'Elijah', service_label: 'Ceramic', from_centavos: 100, to_centavos: 200, reason: 'Typo' }), /Ceramic ₱1 → ₱2 · Typo$/);
	assert.equal(historyLine({ at, kind: 'approved', actor: 'Maria' }), 'Nov 24, 3:10 PM · Maria · Approved');
	for (const [kind, word] of [['booked', 'Booked'], ['completed', 'Completed'], ['cancelled', 'Cancelled'], ['rescheduled', 'Rescheduled']]) {
		assert.ok(historyLine({ at, kind, actor: 'Customer' }).endsWith(word), kind);
	}
});

test('historyLine leaves amounts out when the server sent none', () => {
	assert.equal(historyLine({ at, kind: 'price_changed', actor: 'Elijah', service_label: 'Ceramic coating', reason: 'Extra corrosion found' }),
		'Nov 24, 3:10 PM · Elijah · Ceramic coating price changed · Extra corrosion found');
	assert.equal(historyLine({ at, kind: 'service_added', actor: 'Elijah', service_label: 'Helmet coating' }), 'Nov 24, 3:10 PM · Elijah · Added Helmet coating');
	assert.equal(historyLine({ at, kind: 'service_removed', actor: 'Elijah', service_code: 'helmet' }), 'Nov 24, 3:10 PM · Elijah · Removed helmet');
});

test('historyLine copes with a missing actor, a blank reason, a bad date and an unknown kind', () => {
	assert.equal(historyLine({ at, kind: 'approved', reason: '   ' }), 'Nov 24, 3:10 PM · HERCO staff · Approved');
	assert.match(historyLine({ at: 'nope', kind: 'booked' }), /^Unknown time · HERCO staff · Booked$/);
	assert.match(historyLine({ at, kind: 'mystery', actor: 'A' }), /A · Changed$/);
	assert.match(historyLine({ at, kind: 'price_changed', actor: 'A', service_label: 'X', to_centavos: 5000 }), /X set to ₱50$/);
});

test('editRights needs the grant and a Pending or Booked booking', () => {
	const both = ['adjustPrices', 'editServices'];
	assert.deepEqual(editRights('pending', both), { price: true, services: true });
	assert.deepEqual(editRights('confirmed', ['adjustPrices']), { price: true, services: false });
	assert.deepEqual(editRights('confirmed', ['editServices']), { price: false, services: true });
	assert.deepEqual(editRights('done', both), { price: false, services: false });
	assert.deepEqual(editRights('cancelled', both), { price: false, services: false });
	assert.deepEqual(editRights('pending', []), { price: false, services: false });
	assert.deepEqual(editRights('pending', undefined), { price: false, services: false });
});

test('editRights with workspace pages: price needs viewIncome and Bookings or Booking history, services needs Bookings', () => {
	const all = ['adjustPrices', 'editServices', 'viewIncome'];
	assert.deepEqual(editRights('pending', all, ['Bookings']), { price: true, services: true });
	assert.deepEqual(editRights('confirmed', all, ['Booking history']), { price: true, services: false });
	assert.deepEqual(editRights('pending', all, ['Reports']), { price: false, services: false });
	assert.deepEqual(editRights('pending', ['adjustPrices', 'editServices'], ['Bookings']), { price: false, services: true });
	assert.deepEqual(editRights('done', all, ['Bookings']), { price: false, services: false });
	assert.deepEqual(editRights('pending', all, []), { price: false, services: false });
});

test('expectedCentavos sends the saved price, 0 for quote-only lines without one, and nothing when the price is hidden', () => {
	assert.equal(expectedCentavos({ price_centavos: 179900 }), 179900);
	assert.equal(expectedCentavos({ price_centavos: 0 }), 0);
	assert.equal(expectedCentavos({ price_centavos: 0, quote_required: true }), 0);
	assert.equal(expectedCentavos({ price_centavos: 250000, quote_required: true }), 250000);
	assert.equal(expectedCentavos({ quote_required: true }), 0);
	assert.equal(expectedCentavos({}), undefined);
	assert.equal(expectedCentavos({ price_centavos: null }), undefined);
});

test('bookingWasUpdated notices a different total or different services', () => {
	const same = { originalTotal: 1000, currentTotal: 1000, originalCodes: ['a'], currentCodes: ['a'] };
	assert.equal(bookingWasUpdated(same), false);
	assert.equal(bookingWasUpdated({ ...same, currentTotal: 1500 }), true);
	assert.equal(bookingWasUpdated({ ...same, currentCodes: ['a', 'b'] }), true);
	assert.equal(bookingWasUpdated({ ...same, currentCodes: ['b'] }), true);
	assert.equal(bookingWasUpdated({ ...same, currentCodes: ['a', 'a'] }), true);
});

test('bookingWasUpdated stays quiet when nothing was edited or totals are hidden', () => {
	assert.equal(bookingWasUpdated({ originalTotal: 1000, currentTotal: null, originalCodes: ['a'], currentCodes: null }), false);
	assert.equal(bookingWasUpdated({ originalTotal: null, currentTotal: null, originalCodes: ['a'], currentCodes: ['a'] }), false);
	assert.equal(bookingWasUpdated({ originalTotal: 1000, currentTotal: 1000, originalCodes: ['b', 'a'], currentCodes: ['a', 'b'] }), false);
});

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

test('screens use the shared pieces: editor in both popups, Changes lists, and the customer note', async () => {
	assert.match(await read('../src/lib/shared/ReportDetails.svelte'), /services\?: Snippet; changes\?: Snippet/);
	// Owner 2026-11-24: Reports details are read-only (Changes list only); the Bookings tab popup has the editor and actions.
	const reports = await read('../src/lib/live/ServerStaffRecords.svelte');
	assert.match(reports, /ServerBookingChanges/);
	assert.doesNotMatch(reports, /ServerServiceEdits|ServerReportActions/);
	const popup = await read('../src/lib/live/ServerBookingPopup.svelte');
	assert.match(popup, /ServerServiceEdits[\s\S]*ServerBookingChanges/);
	assert.match(popup, /ServerReportActions[\s\S]*ServerCompletionForm|ServerCompletionForm[\s\S]*ServerReportActions/);
	assert.match(await read('../src/lib/live/ServerStaffBookings.svelte'), /import\('\.\/ServerBookingPopup\.svelte'\)/);
	// The Complete form is created only when opened, so it starts from the latest (possibly edited) price.
	assert.match(popup, /\{#if completeOpen\}<ServerCompletionForm/);

	assert.match(await read('../src/lib/live/ServerBookingHistory.svelte'), /Updated by the shop after inspection/);

	const editor = await read('../src/lib/shared/ServiceLinesEditor.svelte');
	assert.match(editor, /Edit price/);
	assert.match(editor, /role="alert"/);
	assert.match(await read('../src/lib/shared/BookingChangesList.svelte'), /No changes yet/);
});
// Bookings slot filter: no garbled arrow, no unexplained count on the button.
test('the Bookings slot filter has a clean arrow and no bare count', async () => {
	const screen = await read('../src/lib/live/ServerStaffBookings.svelte');
	assert.doesNotMatch(screen, /Â|â€|â–/);
	assert.doesNotMatch(screen, /<summary>[^]*?slot-filter-count[^]*?<\/summary>/);
});
