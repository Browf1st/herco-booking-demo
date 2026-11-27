import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { contactError } from '../src/lib/live/booking-contact.ts';

const read = (path) => readFile(new URL('../' + path, import.meta.url), 'utf8');

test('staff can choose a guest booking on the scheduled path only', async () => {
	const picker = await read('src/lib/live/ManualBooking.svelte');
	assert.match(picker, /\{#if guest && !walkIn\}[\s\S]*?<ServerBooking manualGuest/);
	assert.match(picker, /\{#if !walkIn\}<button[^\n]*>Book without an account/);
	assert.match(picker, /<ServerBooking manualCustomer=\{customer\} walkIn=/);
});

test('guest contact asks for a name, allows an empty mobile, and omits account details', async () => {
	const screen = await read('src/lib/live/ServerBooking.svelte');
	assert.match(screen, /phoneRequired = \$derived\(walkIn \|\| !!manualCustomer\)/);
	assert.match(screen, /\{#if !manualGuest\}<label>\s*<span>Email/);
	assert.match(screen, /manualGuest \? \{ action: 'book_guest' \} : manualCustomer\s*\? \{ action: 'book', customerId:/);
	assert.match(screen, /manualGuest \? booked.reference \?\? booked.id/);
	assert.equal(contactError('   ', '', false), 'Enter your name.');
	assert.equal(contactError('Test Guest', '', false), '');
	assert.match(contactError('Test Guest', '123', false), /leave it blank/);
	assert.equal(contactError('Test Guest', '+63 917 000 0000', false), '');
});

test('the Customers directory offers the group browser, and chronological history no longer does', async () => {
	const [customers, history, group] = await Promise.all([
		read('src/routes/customers/+page.svelte'),
		read('src/lib/live/ServerStaffRecords.svelte'),
		read('src/lib/live/BookingNameGroup.svelte')
	]);
	assert.match(customers, /<BookingNameGroup surface="customers"\s*\/>/);
	assert.match(customers, /\/api\/staff\/customers/);
	// F-026: the global same-name button is gone from Booking history; only the Customers directory keeps the group browser.
	assert.doesNotMatch(history, /BookingNameGroup|same-name/);
	assert.match(history, /Newest first/);
	assert.match(group, /fetch\(resolve\('\/api\/staff\/booking-name-groups'\), \{\s*method: 'POST'/);
	assert.match(group, /body: JSON.stringify\(\{ surface, page: next, \.\.\.\(name \? \{ name \} : \{ q: query \}\) \}\)/);
	assert.match(group, /booking.reference/);
	assert.match(group, /statusLabels\[booking.status\]/);
	assert.match(group, /fmtDate\(booking.date/);
});

test('staff guest cards retain private completion and omit account-only actions', async () => {
	const [card, completion] = await Promise.all([
		read('src/lib/live/ServerStaffBookingCard.svelte'),
		read('src/lib/live/ServerCompletionForm.svelte')
	]);
	assert.match(card, /hasCustomerAccount = \$derived\(booking.customer_id !== null\)/);
	assert.match(card, /canOpenIntake = \$derived\(hasCustomerAccount && permissions.canRequestIntake/);
	assert.match(card, /\{#if canOpenIntake\}[^\n]+Walk-in intake/);
	assert.match(card, /\{#if hasCustomerAccount && \(permissions.can_edit_services \|\| permissions.canComplete\)\}[^\n]+Share customer note\/photos/);
	assert.match(card, /booking.status === 'confirmed' && permissions.canComplete[^\n]+Complete service/);
	assert.match(completion, /private photos[^\n]+\{#if hasCustomerAccount\} Share them/);
});
