import assert from 'node:assert/strict';
import test from 'node:test';
import { oppositeTheme } from '../src/lib/shared/account-menu.ts';
import { entryRange, initials, manilaStamp, refsText, reportPrice, sortReportRows } from '../src/lib/shared/report-ui.ts';

const row = (id, status, priceValue) => ({ id, ref: id, name: id, bike: '', walkIn: false, date: '', time: '', services: '', status, priceValue });

// Avatar initials

test('initials use the first letter of up to two words', () => {
	assert.equal(initials('Brof1st'), 'B');
	assert.equal(initials('TEST UI Rider Gamma'), 'TU');
	assert.equal(initials('  juan   dela cruz '), 'JD');
});

test('initials never come out empty', () => {
	assert.equal(initials(''), '?');
	assert.equal(initials('   '), '?');
});

// Price column

test('a completed booking shows its final price', () => {
	assert.deepEqual(reportPrice('done', '₱1,400.00', '₱1,200.00'), { text: '₱1,400.00', kind: 'final' });
});

test('pending and booked bookings show the original estimate', () => {
	assert.deepEqual(reportPrice('pending', null, '₱850.00'), { text: '₱850.00', kind: 'estimate' });
	assert.deepEqual(reportPrice('confirmed', null, '₱999.00'), { text: '₱999.00', kind: 'estimate' });
});

test('cancelled bookings and unknown prices show a dash', () => {
	assert.equal(reportPrice('cancelled', null, '₱500.00').text, '—');
	assert.equal(reportPrice('pending', null, null).text, '—');
	assert.equal(reportPrice('done', null, '₱500.00').text, '—', 'a completed booking never shows the estimate as if it were final');
	assert.equal(reportPrice('pending', '₱1.00', null).text, '—', 'a final price is ignored before completion');
});

// Sort menu

test('sort by price puts the highest first and rows without a price last', () => {
	const sorted = sortReportRows([row('a', 'pending', 100), row('b', 'cancelled'), row('c', 'done', 900)], 'price');
	assert.deepEqual(sorted.map((item) => item.id), ['c', 'a', 'b']);
});

test('sort by status follows pending, booked, completed, cancelled', () => {
	const sorted = sortReportRows([row('a', 'cancelled'), row('b', 'done'), row('c', 'confirmed'), row('d', 'pending')], 'status');
	assert.deepEqual(sorted.map((item) => item.id), ['d', 'c', 'b', 'a']);
});

test('sort by date keeps the given order and never changes the original list', () => {
	const rows = [row('a', 'done'), row('b', 'pending')];
	assert.deepEqual(sortReportRows(rows, 'date').map((item) => item.id), ['a', 'b']);
	sortReportRows(rows, 'price');
	assert.deepEqual(rows.map((item) => item.id), ['a', 'b']);
});

// Footer "Showing x to y of z entries"

test('the entry range counts a full page and a short last page', () => {
	assert.deepEqual(entryRange(1, 1, 9, 9), { from: 1, to: 9 });
	assert.deepEqual(entryRange(1, 3, 25, 10), { from: 1, to: 10 });
	assert.deepEqual(entryRange(2, 3, 25, 10), { from: 11, to: 20 });
	assert.deepEqual(entryRange(3, 3, 25, 5), { from: 21, to: 25 });
});

test('an empty page has no range', () => {
	assert.deepEqual(entryRange(1, 1, 0, 0), { from: 0, to: 0 });
});

// References in the count cards

test('references are listed only when there are a few', () => {
	assert.equal(refsText(['HG-11', 'HG-15']), 'HG-11, HG-15');
	assert.equal(refsText(['a', 'b', 'c', 'd']), '');
	assert.equal(refsText([]), '');
	assert.equal(refsText(undefined), '');
});

// Philippine time stamps

test('a stamp is shown in Philippine time', () => {
	assert.match(manilaStamp('2026-11-20T08:38:00Z'), /Nov 20, 2026/);
	assert.match(manilaStamp('2026-11-20T08:38:00Z'), /4:38/);
});

test('a missing or broken time reads "Not recorded"', () => {
	assert.equal(manilaStamp(undefined), 'Not recorded');
	assert.equal(manilaStamp(null), 'Not recorded');
	assert.equal(manilaStamp('not a date'), 'Not recorded');
});

// Account menu helpers

test('the theme button switches to the opposite of what is on screen', () => {
	assert.equal(oppositeTheme('light', true), 'dark');
	assert.equal(oppositeTheme('dark', false), 'light');
	assert.equal(oppositeTheme('system', true), 'light');
	assert.equal(oppositeTheme('system', false), 'dark');
});
