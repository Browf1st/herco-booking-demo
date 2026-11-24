import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL('../' + path, import.meta.url), 'utf8');

test('the live reports screen sends the sort, reloads from page 1 and uses the server estimate', async () => {
	const screen = await read('src/lib/live/ServerStaffRecords.svelte');
	assert.match(screen, /report, sort \}\)/);
	assert.match(screen, /onsort=\{\(next\) => \{ sort = next; void load\(\); \}\}/);
	assert.match(screen, /sort=\{result\.sort \?\? sort\} sortAll/);
	// Pending and Booked rows show the booking's current total (owner rule 2026-11-24), not the booking-time estimate.
	assert.match(screen, /const estimate = booking\.total_centavos \?\? undefined/);
	assert.doesNotMatch(screen, /const estimate = booking\.original_total_centavos/);
	assert.doesNotMatch(screen, /price_centavos, 0\)/);
});

test('the Price sort options are hidden without the income permission', async () => {
	const table = await read('src/lib/shared/ReportTable.svelte');
	assert.match(table, /showPrice \? sortOptions : sortOptions\.filter\(\(option\) => !isPriceSort\(option\.value\)\)/);
});

test('the live reports search is sent to the server after a pause and reloads from page 1', async () => {
	const screen = await read('src/lib/live/ServerStaffRecords.svelte');
	const table = await read('src/lib/shared/ReportTable.svelte');
	assert.match(screen, /search: filters\.search/);
	assert.match(screen, /bind:search=\{filters\.search\}/);
	assert.match(screen, /onsearch=\{\(\) => load\(\)\}/);
	assert.match(table, /setTimeout\(\(\) => \{ search = text; onsearch\?\.\(\); \}, 300\)/);
});

test('the demo reports search filters the demo records and goes back to page 1', async () => {
	const screen = await read('src/lib/demo/AdminReports.svelte');
	assert.match(screen, /bind:search=\{filters\.search\}/);
	assert.match(screen, /onsearch=\{\(\) => recordPage = 1\}/);
});

test('reports no longer show the removed labels in either build', async () => {
	for (const path of ['src/lib/live/ServerStaffRecords.svelte', 'src/lib/demo/AdminReports.svelte', 'src/lib/shared/ReportSummary.svelte', 'src/lib/shared/ReportTable.svelte']) {
		const source = await read(path);
		assert.doesNotMatch(source, /Workshop view|How these numbers|records? · Newest first|Total requests logged|Direct visits|Slot released/, path);
	}
	assert.doesNotMatch(await read('src/lib/shared/ReportDetails.svelte'), /Estimated service value/);
});

test('the unsubscribe page only sends the token when the button is pressed', async () => {
	const page = await read('src/routes/reminders/unsubscribe/+page.svelte');
	assert.match(page, /\/api\/reminders\/unsubscribe/);
	assert.match(page, /onclick=\{unsubscribe\}/);
	assert.doesNotMatch(page, /onMount\([^]*unsubscribe\(\)[^]*\}\);\s*<\/script>/);
	assert.match(page, /response\.status === 400 \? 'invalid' : 'error'/);
});

test('the account switch uses the reminders endpoint with a boolean', async () => {
	const live = await read('src/lib/live/ServerReminderSwitch.svelte');
	assert.match(live, /\/api\/account\/reminders/);
	assert.match(live, /JSON\.stringify\(\{ maintenance: next \}\)/);
});
