import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { isVisitHour, parseDateHours, parseScheduleSettings } from '../src/lib/server/schedule-input.ts';

test('visit hours are whole numbers from 0 to 23', () => {
	for (const hour of [0, 8, 9, 16, 17, 23]) assert.equal(isVisitHour(hour), true, String(hour));
	for (const hour of [-1, 24, 25, 9.5, '9', null, undefined, NaN, Infinity, true]) assert.equal(isVisitHour(hour), false, String(hour));
});

test('default hours accept a valid shop day and sort the weekdays', () => {
	const result = parseScheduleSettings({ openHour: 8, closeHour: 20, openWeekdays: [6, 3, 0], confirmOutside: true });
	assert.deepEqual(result.value, { openHour: 8, closeHour: 20, openWeekdays: [0, 3, 6], confirmOutside: true, version: null, confirmedOutsideCount: null });
	assert.equal(parseScheduleSettings({ openHour: 0, closeHour: 24, openWeekdays: [0] }).value.confirmOutside, false);
});

test('version and confirmed outside count are optional and checked', () => {
	const ok = { openHour: 9, closeHour: 17, openWeekdays: [1] };
	const version = '2026-11-23T01:02:03.123456Z';
	const parsed = parseScheduleSettings({ ...ok, confirmOutside: true, version, confirmedOutsideCount: 3 }).value;
	assert.equal(parsed.version, version);
	assert.equal(parsed.confirmedOutsideCount, 3);
	assert.equal(parseScheduleSettings({ ...ok, confirmedOutsideCount: 0 }).value.confirmedOutsideCount, 0);
	for (const bad of [-1, 1.5, '2', NaN, Infinity, true, 1e9]) assert.match(parseScheduleSettings({ ...ok, confirmedOutsideCount: bad }).message, /confirmation count/, String(bad));
	for (const bad of [5, '', 'x'.repeat(41), {}, true]) assert.match(parseScheduleSettings({ ...ok, version: bad }).message, /version/, String(bad));
	assert.equal(parseDateHours({ openHour: 8, closeHour: 12, confirmOutside: true, confirmedOutsideCount: 2 }).value.confirmedOutsideCount, 2);
	assert.match(parseDateHours({ openHour: 8, closeHour: 12, confirmedOutsideCount: -1 }).message, /confirmation count/);
	assert.match(parseDateHours({ openHour: 8, closeHour: 12, confirmedOutsideCount: 'a' }).message, /confirmation count/);
});

test('default hours reject bad hours and weekdays with a clear message', () => {
	const ok = { openHour: 9, closeHour: 17, openWeekdays: [1] };
	assert.match(parseScheduleSettings({ ...ok, closeHour: 9 }).message, /after opening/);
	assert.match(parseScheduleSettings({ ...ok, closeHour: 8 }).message, /after opening/);
	assert.match(parseScheduleSettings({ ...ok, openHour: 24 }).message, /opening and closing/);
	assert.match(parseScheduleSettings({ ...ok, openHour: -1 }).message, /opening and closing/);
	assert.match(parseScheduleSettings({ ...ok, closeHour: 25 }).message, /opening and closing/);
	assert.match(parseScheduleSettings({ ...ok, closeHour: 0 }).message, /opening and closing/);
	assert.match(parseScheduleSettings({ ...ok, openHour: 'nine' }).message, /opening and closing/);
	assert.match(parseScheduleSettings({ ...ok, openWeekdays: [] }).message, /at least one/);
	assert.match(parseScheduleSettings({ ...ok, openWeekdays: [1, 1] }).message, /at least one/);
	assert.match(parseScheduleSettings({ ...ok, openWeekdays: [7] }).message, /at least one/);
	assert.match(parseScheduleSettings({ ...ok, openWeekdays: ['1'] }).message, /at least one/);
	assert.match(parseScheduleSettings({ ...ok, openWeekdays: 'all' }).message, /at least one/);
	assert.match(parseScheduleSettings({ ...ok, confirmOutside: 'yes' }).message, /confirmation/);
	assert.ok(parseScheduleSettings(null).message);
	assert.ok(parseScheduleSettings('text').message);
});

test('own hours for a date use the same limits', () => {
	assert.deepEqual(parseDateHours({ openHour: 8, closeHour: 12 }).value, { openHour: 8, closeHour: 12, confirmOutside: false, confirmedOutsideCount: null });
	assert.match(parseDateHours({ openHour: 12, closeHour: 12 }).message, /after opening/);
	assert.match(parseDateHours({ openHour: 8 }).message, /opening and closing/);
	assert.match(parseDateHours({ openHour: 8, closeHour: 25 }).message, /opening and closing/);
});

test('every route that takes a visit hour uses the 0-23 check, not the old 9-16 range', async () => {
	for (const route of ['bookings/+server.ts', 'bookings/requests/+server.ts', 'staff/bookings/+server.ts', 'staff/manual-booking/+server.ts']) {
		const source = await readFile(new URL(`../src/routes/api/${route}`, import.meta.url), 'utf8');
		assert.match(source, /isVisitHour\(/, route);
		assert.doesNotMatch(source, /hour (<|>) (9|16)\b/, route);
	}
});

test('the settings route and the date-hours action are same-origin, validated and permission-checked in the database', async () => {
	const settings = await readFile(new URL('../src/routes/api/staff/schedule-settings/+server.ts', import.meta.url), 'utf8');
	assert.match(settings, /requireSameOrigin\(event\)/);
	assert.match(settings, /parseScheduleSettings\(/);
	assert.match(settings, /bookings_outside_hours/);
	assert.match(settings, /schedule_changed/);
	assert.match(settings, /Opening hours were changed by someone else\. Reload to see the latest\./);
	assert.match(settings, /p_version: version/);
	assert.match(settings, /p_confirmed_outside: confirmedOutsideCount/);
	const bookings = await readFile(new URL('../src/routes/api/staff/bookings/+server.ts', import.meta.url), 'utf8');
	assert.match(bookings, /requireSameOrigin\(event\)/);
	assert.match(bookings, /set_date_hours/);
	assert.match(bookings, /herco_set_date_hours/);
	assert.match(bookings, /p_confirmed_outside: parsed\.value\.confirmedOutsideCount/);
	assert.match(bookings, /That date has passed\./);
});
