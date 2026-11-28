import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { serviceTypeLabel } from '../src/lib/shared/records-ui.ts';
import { summarizeServiceChange } from '../src/lib/shared/service-change.ts';
import { menuItems } from '../src/lib/live/booking-menu.ts';
import { historyCap, historyLines } from '../src/lib/live/customer-history.ts';

const read = (path) => readFile(new URL('../' + path, import.meta.url), 'utf8');

// F-026: service type tag

test('serviceTypeLabel reads Ceramic, Powder or both from codes or labels', () => {
	assert.equal(serviceTypeLabel(['ceramic']), 'Ceramic');
	assert.equal(serviceTypeLabel(['wheel-colour']), 'Powder');
	assert.equal(serviceTypeLabel(['Ceramic coating', 'Powder coating']), 'Ceramic + Powder');
	assert.equal(serviceTypeLabel(['wheel-colour', 'ceramic', 'helmet']), 'Ceramic + Powder');
	assert.equal(serviceTypeLabel(['Wheel colour']), 'Powder');
});

test('serviceTypeLabel is empty for other services, empty or missing lists', () => {
	assert.equal(serviceTypeLabel(['helmet']), '');
	assert.equal(serviceTypeLabel([]), '');
	assert.equal(serviceTypeLabel(undefined), '');
	assert.equal(serviceTypeLabel([null, undefined]), '');
});

// F-024: Actions menu items

const base = { status: 'confirmed', visitHour: 10, future: true, requestsReady: true, hasOpenRequest: false };

test('only a pending visit offers Edit service; a confirmed one offers View service', () => {
	assert.deepEqual(menuItems({ ...base, status: 'pending' }), ['reschedule', 'cancel', 'edit-service']);
	assert.deepEqual(menuItems(base), ['reschedule', 'cancel', 'view-service']);
});

test('an open request offers Withdraw request instead of Reschedule and Cancel', () => {
	assert.deepEqual(menuItems({ ...base, status: 'pending', hasOpenRequest: true }), ['withdraw', 'edit-service']);
	assert.deepEqual(menuItems({ ...base, hasOpenRequest: true }), ['withdraw', 'view-service']);
});

test('a shop-priced pending booking can be viewed but no longer edited', () => {
	assert.deepEqual(menuItems({ ...base, status: 'pending', shopPriced: true }), ['reschedule', 'cancel', 'view-service']);
});

test('past, done, cancelled and walk-in bookings offer View service only', () => {
	assert.deepEqual(menuItems({ ...base, status: 'pending', future: false }), ['view-service']);
	assert.deepEqual(menuItems({ ...base, status: 'done' }), ['view-service']);
	assert.deepEqual(menuItems({ ...base, status: 'cancelled' }), ['view-service']);
	assert.deepEqual(menuItems({ ...base, status: 'pending', visitHour: null }), ['view-service']);
});

test('request items stay hidden until the request check has finished, but services stay reachable', () => {
	assert.deepEqual(menuItems({ ...base, status: 'pending', requestsReady: false }), ['edit-service']);
	assert.deepEqual(menuItems({ ...base, status: 'pending', requestsReady: false, hasOpenRequest: true }), ['edit-service']);
});

// F-024: customer change log

const at = '2026-11-26T02:10:00Z';

test('change log lines show from to pesos, You or Shop and Philippine time', () => {
	const [line] = historyLines([{ at, kind: 'price_changed', actor: 'shop', service_label: 'Ceramic coating', from_centavos: 250000, to_centavos: 280000 }]);
	assert.equal(line.actor, 'Shop');
	assert.match(line.text, /Ceramic coating price changed from .2,500\.00 to .2,800\.00/);
	assert.match(line.when, /10:10/);
	assert.equal(historyLines([{ at, kind: 'rescheduled', actor: 'you' }])[0].actor, 'You');
});

test('change log never shows staff names, reasons or notes even if the server sent them', () => {
	const lines = historyLines([{ at, kind: 'price_changed', actor: 'shop', service_label: 'Ceramic', from_centavos: 100, to_centavos: 200,
		reason: 'Extra corrosion', staff_name: 'Maria Santos', note: 'private', actor_name: 'Maria' }]);
	assert.doesNotMatch(JSON.stringify(lines), /corrosion|Maria|private/);
});

test('change log handles added, removed, missing amounts, bad dates, newest first and the cap', () => {
	assert.match(historyLines([{ at, kind: 'service_added', actor: 'shop', service_label: 'Helmet', to_centavos: 29900 }])[0].text, /Added Helmet \(.299\.00\)/);
	assert.match(historyLines([{ at, kind: 'service_removed', actor: 'you', service_label: 'Helmet', from_centavos: 29900 }])[0].text, /Removed Helmet/);
	assert.match(historyLines([{ at, kind: 'price_changed', actor: 'shop' }])[0].text, /Service price changed/);
	assert.deepEqual(historyLines([{ at: 'nope', kind: 'booked', actor: 'you' }]), []);
	assert.deepEqual(historyLines([]), []);
	const two = historyLines([{ at: '2026-11-20T01:00:00Z', kind: 'booked', actor: 'you' }, { at: '2026-11-21T01:00:00Z', kind: 'approved', actor: 'shop' }]);
	assert.equal(two[0].text, 'Booking confirmed');
	const many = Array.from({ length: historyCap + 50 }, (_, index) => ({ at: new Date(Date.UTC(2026, 0, 1, 0, index)).toISOString(), kind: 'booked', actor: 'you' }));
	assert.equal(historyLines(many).length, historyCap);
});

// F-026: edit service summary

const current = [{ code: 'ceramic', label: 'Ceramic', centavos: 250000 }, { code: 'helmet', label: 'Helmet', centavos: 30000 }];
const options = [{ code: 'wheel-colour', label: 'Wheel colour', centavos: 100000 }, { code: 'quote', label: 'Custom', quote: true }];

test('service change summary lists added and removed lines and the new total', () => {
	const result = summarizeServiceChange(current, options, ['ceramic', 'wheel-colour']);
	assert.deepEqual(result.added.map((line) => line.code), ['wheel-colour']);
	assert.deepEqual(result.removed.map((line) => line.code), ['helmet']);
	assert.equal(result.totalCentavos, 350000);
	assert.equal(result.problem, '');
});

test('service change summary blocks no change and an empty booking, and has no total for quotes', () => {
	assert.equal(summarizeServiceChange(current, options, ['ceramic', 'helmet']).problem, 'Nothing has changed yet.');
	assert.match(summarizeServiceChange(current, options, []).problem, /at least one service/);
	assert.equal(summarizeServiceChange(current, options, ['ceramic', 'quote']).totalCentavos, undefined);
});

// Shared pattern wiring (source checks)

test('all three views use the shared BookingCard and ReportDetails', async () => {
	const [customer, staffCard, records, bookings, popup, customerPopup] = await Promise.all([
		read('src/lib/live/ServerBookingHistory.svelte'), read('src/lib/live/ServerStaffBookingCard.svelte'), read('src/lib/live/ServerStaffRecords.svelte'),
		read('src/lib/live/ServerStaffBookings.svelte'), read('src/lib/live/ServerBookingPopup.svelte'), read('src/lib/live/ServerCustomerBookingPopup.svelte')
	]);
	assert.match(customer, /<BookingCard /);
	assert.match(staffCard, /<BookingCard /);
	assert.match(records, /ServerStaffBookingCard/);
	assert.match(bookings, /ServerStaffBookingCard/);
	assert.match(popup, /<ReportDetails /);
	assert.match(customerPopup, /<ReportDetails \{detail\} variant="customer"/);
	assert.match(records, /ServerBookingPopup\.svelte/);
	assert.match(staffCard, /services=\{serviceNames\}/);
	assert.match(customer, /services=\{services\.map/);
});

test('customer card has one Actions menu and no per-card request buttons', async () => {
	const customer = await read('src/lib/live/ServerBookingHistory.svelte');
	assert.match(customer, /<BookingActionsMenu/);
	assert.doesNotMatch(customer, /Request rescheduling|Request cancellation|View details or edit services/);
	const menu = await read('src/lib/live/BookingActionsMenu.svelte');
	assert.match(menu, /Escape/);
	assert.match(menu, /onpointerdown/);
	assert.match(menu, /actionsMenu/);
});

test('customer popup and change log never read staff-only fields', async () => {
	const [popup, log, history] = await Promise.all([read('src/lib/live/ServerCustomerBookingPopup.svelte'), read('src/lib/live/CustomerChangeLog.svelte'), read('src/lib/live/customer-history.ts')]);
	for (const source of [log, history]) assert.doesNotMatch(source, /staff_name|private_|approval_note|customer_phone|customer_email|\.reason\b/);
	assert.doesNotMatch(popup, /staff_name|private_|approval_note|customer_phone|customer_email/);
	assert.match(log, /\/api\/bookings\/history/);
	const details = await read('src/lib/shared/ReportDetails.svelte');
	assert.match(details, /!customer && \(onEditPrice \|\| onEditService\)/);
	assert.match(details, /\{#if !customer\}\s*<p class="contact">/);
});

test('staff popup puts Edit price and Edit service top right only when the grants allow', async () => {
	const popup = await read('src/lib/live/ServerBookingPopup.svelte');
	assert.match(popup, /canEditPrice = \$derived\(canEditLines && rights\.price && showMoney/);
	assert.match(popup, /onEditService=\{canEditLines && servicesEditable/);
});

test('price edit shows one box per part with a live total, and the reason stays staff-only', async () => {
	const editor = await read('src/lib/shared/ServiceLinesEditor.svelte');
	// Owner decision 2026-11-28: each part (base plus each option) is its own editable box; the total auto-sums.
	assert.match(editor, /class="parts-edit"/);
	assert.match(editor, /New total/);
	assert.match(editor, /now \{peso\(part\.current\)\}/);
	assert.match(editor, /staff only/);
	const edits = await read('src/lib/live/ServerServiceEdits.svelte');
	assert.match(edits, /expectedCentavos: expected, parts, reason/);
});

test('the recorded-name bookings feature is removed everywhere', async () => {
	const records = await read('src/lib/live/ServerStaffRecords.svelte');
	assert.doesNotMatch(records, /same-name|BookingNameGroup|bookingName/);
	assert.doesNotMatch(await read('src/routes/customers/+page.svelte'), /BookingNameGroup/);
});

test('the slot filter is one contained control with the shared chevron and one options style', async () => {
	const screen = await read('src/lib/live/ServerStaffBookings.svelte');
	assert.match(screen, /<ActionIcon name="down" \/>/);
	assert.doesNotMatch(screen, /\.filter-options|min-width: 10rem|class="filter-options"/);
	assert.equal((screen.match(/slot-filter-options \) \{|slot-filter-options\) \{/g) ?? []).length, 1);
});
