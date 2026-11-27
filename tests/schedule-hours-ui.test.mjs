import assert from 'node:assert/strict';
import test from 'node:test';
import { closeText, defaultSettings, hourRange, hoursForDate, hoursIssue, hourText, slotPreview, visitsOutside } from '../src/lib/shared/schedule-hours.ts';

// 2026-11-25 is a Wednesday, 2026-11-23 a Monday, 2026-11-29 a Sunday.
const settings = defaultSettings();

test('hour names use 12-hour time and midnight closes the day', () => {
	assert.equal(hourText(0), '12 AM');
	assert.equal(hourText(12), '12 PM');
	assert.equal(hourText(16), '4 PM');
	assert.equal(closeText(24), '12 AM (midnight)');
});

test('the slot preview lists the first, second and last hour with the count', () => {
	assert.equal(slotPreview(9, 17), '9 AM, 10 AM … 5 PM · 9 slots a day');
	assert.equal(slotPreview(8, 20), '8 AM, 9 AM … 8 PM · 13 slots a day');
});

test('the slot preview lists every hour when there are three or fewer', () => {
	assert.equal(slotPreview(9, 11), '9 AM, 10 AM, 11 AM · 3 slots a day');
	assert.equal(slotPreview(9, 10), '9 AM, 10 AM · 2 slots a day');
});

test('the slot preview is empty when closing is not after opening', () => {
	assert.equal(slotPreview(10, 10), '');
	assert.equal(slotPreview(12, 9), '');
});

test('a midnight close (24) does not offer a 12 AM slot: the last slot is 11 PM', () => {
	const hrs = hoursForDate({ ...settings, closeHour: 24 }, '2026-11-25').hours;
	assert.equal(hrs.at(-1), 23);
	assert.equal(hrs.includes(24), false);
});

test('hourRange stops an hour before closing and never goes negative', () => {
	assert.deepEqual(hourRange(9, 12), [9, 10, 11]);
	assert.deepEqual(hourRange(23, 24), [23]);
	assert.deepEqual(hourRange(5, 5), []);
	assert.deepEqual(hourRange(8, 3), []);
});

test('invalid hours and open days explain the problem in plain words', () => {
	assert.equal(hoursIssue(9, 17, [3]), '');
	assert.equal(hoursIssue(9, 9), 'Closing time must be after opening time.');
	assert.equal(hoursIssue(17, 9, [3]), 'Closing time must be after opening time.');
	assert.equal(hoursIssue(9, 17, []), 'Pick at least one open day.');
});

test('starting values give 9 AM to 5 PM slots on Wednesday to Sunday only', () => {
	assert.deepEqual(hoursForDate(settings, '2026-11-25').hours, [9, 10, 11, 12, 13, 14, 15, 16, 17]);
	assert.equal(hoursForDate(settings, '2026-11-29').closed, false);
	assert.equal(hoursForDate(settings, '2026-11-23').closed, true);
	assert.equal(hoursForDate(settings, '2026-11-24').closed, true);
});

test('new default hours apply to every open date without its own hours', () => {
	const next = { ...settings, openHour: 8, closeHour: 20 };
	assert.equal(hoursForDate(next, '2026-11-25').hours.length, 13);
	assert.equal(hoursForDate(next, '2026-11-25').hours.at(-1), 20);
});

test('a date with its own hours keeps them when the default hours change', () => {
	const next = { ...settings, openHour: 10, closeHour: 12 };
	const day = hoursForDate(next, '2026-11-25', { ownOpen: 7, ownClose: 21 });
	assert.equal(day.openHour, 7);
	assert.equal(day.hours.length, 15);
});

test('own hours for one date, e.g. 8 AM to 12 PM, show 8 AM to 12 PM', () => {
	assert.deepEqual(hoursForDate(settings, '2026-11-26', { ownOpen: 8, ownClose: 12 }).hours, [8, 9, 10, 11, 12]);
});

test('a closed date has no hours even on an open weekday, and beats own hours', () => {
	assert.deepEqual(hoursForDate(settings, '2026-11-25', { closed: true }).hours, []);
	assert.equal(hoursForDate(settings, '2026-11-25', { closed: true, ownOpen: 8, ownClose: 12 }).closed, true);
});

test('an Open date on a closed weekday uses the default hours', () => {
	const day = hoursForDate(settings, '2026-11-23', { open: true });
	assert.equal(day.closed, false);
	assert.equal(day.hours.length, 9);
});

test('unticking a weekday closes it, but an Open date on it stays open', () => {
	const next = { ...settings, openWeekdays: [0, 4, 5, 6] };
	assert.equal(hoursForDate(next, '2026-11-25').closed, true);
	assert.equal(hoursForDate(next, '2026-11-25', { open: true }).closed, false);
});

test('visits outside the new hours are listed in date and hour order, with no names', () => {
	const visits = [
		{ reference: 'B', date: '2026-11-26', hour: 18 },
		{ reference: 'A', date: '2026-11-25', hour: 19 },
		{ reference: 'C', date: '2026-11-25', hour: 10 }
	];
	const before = (date) => hoursForDate({ ...settings, closeHour: 20 }, date);
	const after = (date) => hoursForDate(settings, date);
	assert.deepEqual(visitsOutside(visits, before, after).map(visit => visit.reference), ['A', 'B']);
});

test('visits already outside the old hours are not listed again', () => {
	const visits = [{ reference: 'A', date: '2026-11-25', hour: 19 }];
	const after = (date) => hoursForDate(settings, date);
	assert.deepEqual(visitsOutside(visits, after, after), []);
});

test('visits on a newly closed weekday are listed', () => {
	const visits = [{ reference: 'A', date: '2026-11-25', hour: 10 }];
	const before = (date) => hoursForDate(settings, date);
	const after = (date) => hoursForDate({ ...settings, openWeekdays: [0, 4, 5, 6] }, date);
	assert.equal(visitsOutside(visits, before, after).length, 1);
});
