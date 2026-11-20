import assert from 'node:assert/strict';
import test from 'node:test';
import { backspaceDigits, codeLength, codeValue, emptyDigits, fillDigits, maskEmail } from '../src/lib/live/code-digits.ts';
import { bookingGroup, groupBookings, initialGroup } from '../src/lib/live/booking-groups.ts';

// Verification code boxes

test('code length follows the setting and falls back to 6', () => {
	assert.equal(codeLength(6), 6);
	assert.equal(codeLength(8), 8);
	assert.equal(codeLength(10), 10);
	for (const bad of [undefined, null, 0, -6, 5, 11, 6.5, '8', NaN]) assert.equal(codeLength(bad), 6);
});

test('typing one digit fills that box and moves to the next', () => {
	const result = fillDigits(['', '', '', '', '', ''], 0, '4', 6);
	assert.deepEqual(result.digits, ['4', '', '', '', '', '']);
	assert.equal(result.focus, 1);
});

test('letters and symbols are ignored', () => {
	const result = fillDigits(['1', '', '', '', '', ''], 1, 'a', 6);
	assert.deepEqual(result.digits, ['1', '', '', '', '', '']);
	assert.equal(result.focus, 1);
});

test('pasting a full code fills every box, even from a middle box', () => {
	const result = fillDigits(['', '', '9', '', '', ''], 2, ' 123-456 ', 6);
	assert.deepEqual(result.digits, ['1', '2', '3', '4', '5', '6']);
	assert.equal(result.focus, 5);
});

test('pasting part of a code fills from the current box and stops at the end', () => {
	const result = fillDigits(['1', '2', '', '', '', ''], 4, '789', 6);
	assert.deepEqual(result.digits, ['1', '2', '', '', '7', '8']);
	assert.equal(result.focus, 5);
});

test('a code longer than the boxes is cut to fit', () => {
	assert.deepEqual(fillDigits([], 0, '12345678', 6).digits, ['1', '2', '3', '4', '5', '6']);
});

test('clearing a box leaves the others alone', () => {
	const result = fillDigits(['1', '2', '3', '', '', ''], 1, '', 6);
	assert.deepEqual(result.digits, ['1', '', '3', '', '', '']);
});

test('8-digit codes get 8 boxes', () => {
	assert.deepEqual(emptyDigits(8), ['', '', '', '', '', '', '', '']);
});

// Regression (QA 2026-11-20): editing a middle box shifted later digits one box left.
test('clearing a middle digit keeps the later digits in their boxes', () => {
	const result = backspaceDigits(['1', '2', '3', '4', '5', '6'], 2);
	assert.deepEqual(result.digits, ['1', '2', '', '4', '5', '6']);
	assert.equal(result.focus, 2);
});

test('backspace on an empty box clears the box before it only', () => {
	const result = backspaceDigits(['1', '2', '3', '', '5', '6'], 3);
	assert.deepEqual(result.digits, ['1', '2', '', '', '5', '6']);
	assert.equal(result.focus, 2);
	assert.deepEqual(backspaceDigits(['', '', '', '', '', ''], 0).digits, ['', '', '', '', '', '']);
});

test('typing into a box after a gap stays in that box', () => {
	const result = fillDigits(['1', '2', '', '', '', ''], 3, '7', 6);
	assert.deepEqual(result.digits, ['1', '2', '', '7', '', '']);
});

test('the code is only complete when every box has a digit', () => {
	assert.equal(codeValue(['1', '2', '', '4', '5', '6']), '');
	assert.equal(codeValue(['1', '2', '3', '4', '5', '6']), '123456');
	assert.equal(codeValue(emptyDigits(6)), '');
});

test('the email is partly hidden on the code screen', () => {
	assert.equal(maskEmail('jamie.reyes@example.com'), 'ja***@example.com');
	assert.equal(maskEmail('j@example.com'), 'j***@example.com');
	assert.equal(maskEmail('not-an-email'), 'not-an-email');
});

// My Bookings sections

const booking = (id, status, visit_date, visit_hour = 10) => ({ id, status, visit_date, visit_hour });

// Fixed "today" for these tests: visits on or after 2026-11-20 count as future.
const isFuture = (b) => b.visit_date >= '2026-11-20';

test('each status lands in the right section', () => {
	assert.equal(bookingGroup(booking('a', 'pending', '2026-12-01'), false, true), 'upcoming');
	assert.equal(bookingGroup(booking('a', 'confirmed', '2026-12-01'), false, true), 'upcoming');
	assert.equal(bookingGroup(booking('a', 'confirmed', '2026-12-01'), true, true), 'requests');
	assert.equal(bookingGroup(booking('a', 'done', '2026-12-01'), true, true), 'past');
	assert.equal(bookingGroup(booking('a', 'cancelled', '2026-12-01'), false, true), 'cancelled');
	assert.equal(bookingGroup(booking('a', 'cancelled', '2026-10-01'), false, false), 'cancelled');
});

// Regression (misuse test 2026-11-20): unfinished bookings from past dates stayed in Upcoming forever.
test('past visits the shop never closed go to Past, not Upcoming', () => {
	assert.equal(bookingGroup(booking('a', 'confirmed', '2026-10-01'), false, false), 'past');
	assert.equal(bookingGroup(booking('a', 'pending', '2026-10-01'), true, false), 'past');
});

test('upcoming visits are soonest first, walk-ins included; past visits latest first', () => {
	const groups = groupBookings([
		booking('late', 'pending', '2026-12-05', 9),
		booking('walk', 'confirmed', '2026-12-01', null),
		booking('soon', 'confirmed', '2026-12-01', 14),
		booking('done', 'done', '2026-11-01'),
		booking('stale', 'confirmed', '2026-11-10')
	], new Set(), isFuture);
	assert.deepEqual(groups.upcoming.map(b => b.id), ['walk', 'soon', 'late']);
	assert.deepEqual(groups.past.map(b => b.id), ['stale', 'done']);
	assert.equal(groups.requests.length + groups.cancelled.length, 0);
});

test('no bookings gives empty sections and opens Upcoming', () => {
	const groups = groupBookings([], new Set(), isFuture);
	assert.equal(initialGroup(groups), 'upcoming');
});

test('opens the first section with bookings, or the just-submitted booking', () => {
	const groups = groupBookings([booking('old', 'done', '2026-10-01'), booking('new', 'pending', '2026-12-01')], new Set(['new']), isFuture);
	assert.equal(initialGroup(groups), 'requests');
	assert.equal(initialGroup(groups, 'old'), 'past');
	assert.equal(initialGroup(groups, 'missing'), 'requests');
});
