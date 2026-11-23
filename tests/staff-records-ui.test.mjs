import assert from 'node:assert/strict';
import test from 'node:test';
import { pageCount } from '../src/lib/shared/paging.ts';
import { activeFilterCount, badgeStatus, rangeIssue, servicesLine, statusIcons, statusLabels } from '../src/lib/shared/records-ui.ts';

const none = { search: '', status: 'all', source: 'all' };

// Filters (n)

test('no hidden filter changed counts as zero', () => {
	assert.equal(activeFilterCount(none), 0);
});

test('each changed search, status or source adds one', () => {
	assert.equal(activeFilterCount({ ...none, search: 'juan' }), 1);
	assert.equal(activeFilterCount({ ...none, search: 'juan', status: 'done' }), 2);
	assert.equal(activeFilterCount({ search: 'juan', status: 'done', source: 'walk-in' }), 3);
});

test('a search of only spaces does not count', () => {
	assert.equal(activeFilterCount({ ...none, search: '   ' }), 0);
});

test('the status filter is left out when the screen has no status field', () => {
	assert.equal(activeFilterCount({ ...none, status: 'done' }, false), 0);
	assert.equal(activeFilterCount({ search: 'a', status: 'done', source: 'online' }, false), 2);
});

// Date range check

const dates = { preset: 'all', from: '2026-11-01', through: '2026-11-23', exact: '2026-11-23' };

test('ready-made periods never report a date problem', () => {
	for (const preset of ['all', 'today', 'week', 'month']) assert.equal(rangeIssue({ ...dates, preset, from: '', through: '' }), '');
});

test('a custom range needs both dates in order', () => {
	assert.equal(rangeIssue({ ...dates, preset: 'custom' }), '');
	assert.equal(rangeIssue({ ...dates, preset: 'custom', from: '2026-11-23', through: '2026-11-23' }), '');
	assert.match(rangeIssue({ ...dates, preset: 'custom', from: '2026-11-24' }), /end date on or after the start date/);
	assert.match(rangeIssue({ ...dates, preset: 'custom', from: '' }), /Choose both dates/);
	assert.match(rangeIssue({ ...dates, preset: 'custom', through: '' }), /Choose both dates/);
});

test('regression: a custom range longer than the server allows is caught before loading', () => {
	assert.equal(rangeIssue({ ...dates, preset: 'custom', from: '2025-11-23', through: '2026-11-23' }), '', '366 days inclusive is allowed');
	assert.match(rangeIssue({ ...dates, preset: 'custom', from: '2025-11-22', through: '2026-11-23' }), /up to 366 days/);
	assert.equal(rangeIssue({ ...dates, preset: 'custom', from: '2024-01-01', through: '2024-12-31' }), '', 'leap year: 365 days apart');
	assert.match(rangeIssue({ ...dates, preset: 'custom', from: 'not-a-date', through: 'zzz' }), /366 days|Choose both dates/);
});

test('a specific date needs a date', () => {
	assert.equal(rangeIssue({ ...dates, preset: 'date' }), '');
	assert.equal(rangeIssue({ ...dates, preset: 'date', exact: '' }), 'Choose an appointment date.');
});

// Card line "Bike · N services"

test('the card line shows the bike and the number of services', () => {
	assert.equal(servicesLine('Honda Click', 2), 'Honda Click · 2 services');
	assert.equal(servicesLine('Honda Click', 1), 'Honda Click · 1 service');
});

test('the card line leaves out what is missing', () => {
	assert.equal(servicesLine('', 3), '3 services');
	assert.equal(servicesLine(undefined, 1), '1 service');
	assert.equal(servicesLine('  Yamaha NMAX  ', 0), 'Yamaha NMAX');
	assert.equal(servicesLine('', 0), '');
});

test('a bike name with markup stays plain text', () => {
	assert.equal(servicesLine('<b>Honda</b>', 1), '<b>Honda</b> · 1 service');
});

// Status badge

test('every status has a label and its own icon, so colour is not the only clue', () => {
	assert.deepEqual(Object.keys(statusLabels).sort(), Object.keys(statusIcons).sort());
	assert.equal(new Set(Object.values(statusIcons)).size, Object.keys(statusIcons).length);
	assert.equal(statusLabels.confirmed, 'Booked');
});

test('a confirmed booking uses the booked badge colour and the others keep their name', () => {
	assert.equal(badgeStatus('confirmed'), 'booked');
	for (const status of ['pending', 'done', 'cancelled']) assert.equal(badgeStatus(status), status);
});

// Pager (shared with the activity log)

test('the pager never shows page 0 of 0', () => {
	assert.equal(pageCount(0, 10), 1);
	assert.equal(pageCount(10, 10), 1);
	assert.equal(pageCount(11, 10), 2);
});
