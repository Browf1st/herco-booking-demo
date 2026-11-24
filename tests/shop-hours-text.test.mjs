import assert from 'node:assert/strict';
import test from 'node:test';
import { formatClosedDays, formatDays, formatShopHours } from '../src/lib/shared/shop-hours-text.ts';

test('the starting hours read "Wed to Sun, 9 AM to 5 PM"', () => {
	const result = formatShopHours({ openHour: 9, closeHour: 17, openWeekdays: [0, 3, 4, 5, 6] });
	assert.equal(result.text, 'Wed to Sun, 9 AM to 5 PM');
	assert.equal(formatClosedDays([0, 3, 4, 5, 6]), 'Mon, Tue');
});

test('three or more days in a row become a range, Monday first', () => {
	assert.equal(formatDays([1, 2, 3]), 'Mon to Wed');
	assert.equal(formatDays([5, 6, 0]), 'Fri to Sun');
	assert.equal(formatDays([1, 2, 3, 4, 5, 6]), 'Mon to Sat');
	assert.equal(formatDays([0, 1, 2, 3, 4, 5]), 'Mon to Fri, Sun');
});

test('days that are not in a row are listed', () => {
	assert.equal(formatDays([1, 3, 5]), 'Mon, Wed, Fri');
	assert.equal(formatDays([5, 3, 1]), 'Mon, Wed, Fri');
});

test('two days in a row are listed, one day stands alone, a range and a day can mix', () => {
	assert.equal(formatDays([1, 2]), 'Mon, Tue');
	assert.equal(formatDays([4]), 'Thu');
	assert.equal(formatDays([1, 3, 4, 5]), 'Mon, Wed to Fri');
});

test('the week does not wrap from Sunday back to Monday', () => {
	assert.equal(formatDays([6, 0, 1]), 'Mon, Sat, Sun');
});

test('all seven days read "Every day" and nothing is closed', () => {
	const result = formatShopHours({ openHour: 8, closeHour: 20, openWeekdays: [0, 1, 2, 3, 4, 5, 6] });
	assert.equal(result.text, 'Every day, 8 AM to 8 PM');
	assert.equal(formatClosedDays([0, 1, 2, 3, 4, 5, 6]), '');
});

test('midnight and noon use 12-hour names', () => {
	assert.equal(formatShopHours({ openHour: 0, closeHour: 24, openWeekdays: [1] }).hours, '12 AM to 12 AM');
	assert.equal(formatShopHours({ openHour: 12, closeHour: 18, openWeekdays: [1] }).hours, '12 PM to 6 PM');
});
