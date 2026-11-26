import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL('../' + path, import.meta.url), 'utf8');

test('the hours card sends the version, offers Reload after schedule_changed and keeps the new version', async () => {
	const card = await read('src/lib/shared/OpeningHoursCard.svelte');
	assert.match(card, /\.\.\.\(version && \{ version \}\)/);
	assert.match(card, /error instanceof ScheduleChanged\) changed = true/);
	assert.match(card, /\{#if changed\}[^]*onclick=\{reload\}>Reload</);
	assert.match(card, /version = \(await onreload\(\)\.catch\(\(\) => undefined\)\)\?\.version \?\? version/);
	// Reload clears the form and uses the freshly loaded values and version.
	assert.match(card, /saved = \{ \.\.\.fresh \}; version = fresh\.version;/);
	assert.match(card, /openHour = fresh\.openHour; closeHour = fresh\.closeHour; weekdays = \[\.\.\.fresh\.openWeekdays\]/);
});

test('Save anyway sends the number of bookings shown, and a second 409 shows the "more bookings" line', async () => {
	const card = await read('src/lib/shared/OpeningHoursCard.svelte');
	const date = await read('src/lib/shared/DateHoursPanel.svelte');
	for (const source of [card, date]) {
		assert.match(source, /confirmOutside \? outside\?\.count : undefined/);
		assert.match(source, /moreOutside = confirmOutside && Boolean\(outside\)/);
		assert.match(source, /more=\{moreOutside\}/);
	}
	const warning = await read('src/lib/shared/OutsideHoursWarning.svelte');
	assert.match(warning, /More bookings are now outside the new hours\./);
});

test('the live screen sends version, confirmedOutsideCount and turns schedule_changed into ScheduleChanged', async () => {
	const live = await read('src/lib/live/ServerStaffBookings.svelte');
	assert.match(live, /result\?\.code === 'schedule_changed'\) throw new ScheduleChanged/);
	assert.match(live, /confirmedOutsideCount/);
	assert.match(live, /saveSchedule\('PUT', '\/api\/staff\/schedule-settings', \{ \.\.\.values, \.\.\.confirmation\(confirmOutside, count\) \}\)/);
	assert.match(live, /saveSchedule\('POST', '\/api\/staff\/bookings', \{ \.\.\.action, date, \.\.\.confirmation\(confirmOutside, count\) \}\)/);
});


test('the unsubscribe done state links to the Account page', async () => {
	const page = await read('src/routes/reminders/unsubscribe/+page.svelte');
	assert.match(page, /<a href=\{resolve\('\/account'\)\}>turn them back on in your Account<\/a>/);
});

test('the report Email button encodes the address and the phone link keeps digits and + only', async () => {
	const details = await read('src/lib/shared/ReportDetails.svelte');
	assert.match(details, /'mailto:' \+ encodeURIComponent\(detail\.email\)/);
	assert.match(details, /'tel:' \+ phone\.replace\(\/\[\^\\d\+\]\/g, ''\)/);
	// The encoded address cannot add a cc or body.
	const href = 'mailto:' + encodeURIComponent('a@b.com?cc=x@y.com&body=hi');
	assert.doesNotMatch(href, /[?&]/);
});

test('the Account menu only points aria-controls at the panel while it exists', async () => {
	const menu = await read('src/lib/shared/AccountMenu.svelte');
	assert.match(menu, /aria-controls=\{open \? 'account-panel' : undefined\}/);
	assert.doesNotMatch(menu, /aria-controls="account-panel"/);
});
