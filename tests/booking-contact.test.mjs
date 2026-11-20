import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { contactError, slotFromHour } from '../src/lib/live/booking-contact.ts';
import { isValidMobile } from '../src/lib/shared/mobile.ts';

test('review time uses a full HH:00 slot (regression: "11:undefined AM")', () => {
	assert.equal(slotFromHour('11'), '11:00');
	assert.equal(slotFromHour(9), '9:00');
	assert.equal(slotFromHour('16'), '16:00');
	assert.doesNotMatch(slotFromHour('11'), /undefined/);
});

test('every live booking time label passes a full slot to fmtSlot', async () => {
	const source = await readFile(new URL('../src/lib/live/ServerBooking.svelte', import.meta.url), 'utf8');
	assert.doesNotMatch(source, /fmtSlot\(visitHour\)/);
});

test('online customers may leave the mobile number blank', () => {
	assert.equal(contactError('Jamie Reyes', '', false), '');
	assert.equal(contactError('Jamie Reyes', '   ', false), '');
	assert.equal(contactError('Jamie Reyes', '0917 000 0000', false), '');
});

test('a typed mobile number must still look valid', () => {
	assert.match(contactError('Jamie Reyes', '12', false), /leave it blank/);
	assert.match(contactError('Jamie Reyes', 'abc', false), /leave it blank/);
	assert.equal(contactError('Jamie Reyes', '+63 917-000-0000', false), '');
});

// Regression (QA 2026-11-20): letters or symbols could pass as a mobile number.
test('mobile numbers use the same rule as the profile and the server', () => {
	assert.equal(isValidMobile('0917 000 0000'), true);
	assert.equal(isValidMobile('+63 (917) 000-0000'), true);
	for (const bad of ['abcdefg', '-------', '123', '0917a000000', '1234567890123456', '++639170000000', '']) {
		assert.equal(isValidMobile(bad), false, bad);
	}
	assert.match(contactError('Jamie Reyes', '0917a000000', false), /leave it blank/);
	assert.equal(contactError('Jamie Reyes', '0917a000000', true), 'Enter a valid mobile number.');
});

test('the booking server checks a typed mobile number', async () => {
	const source = await readFile(new URL('../src/routes/api/bookings/+server.ts', import.meta.url), 'utf8');
	assert.match(source, /isValidMobile\(body\.phone\)/);
});

test('walk-ins and staff bookings still require a mobile number', () => {
	assert.equal(contactError('Jamie Reyes', '', true), 'Enter a valid mobile number.');
	assert.equal(contactError('Jamie Reyes', '12345', true), 'Enter a valid mobile number.');
	assert.equal(contactError('Jamie Reyes', '0917 000 0000', true), '');
});

test('name is always required', () => {
	assert.equal(contactError('', '0917 000 0000', false), 'Enter your name.');
	assert.equal(contactError('   ', '', true), 'Enter your name.');
});
