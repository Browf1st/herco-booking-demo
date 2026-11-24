import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL('../' + path, import.meta.url), 'utf8');

test('the live reports screen sends the sort, reloads from page 1 and uses the server estimate', async () => {
	const screen = await read('src/lib/live/ServerStaffRecords.svelte');
	assert.match(screen, /report, sort \}\)/);
	assert.match(screen, /onsort=\{\(next\) => \{ sort = next; void load\(\); \}\}/);
	assert.match(screen, /sort=\{result\.sort \?\? sort\} sortAll/);
	assert.match(screen, /original_total_centavos \?\? undefined/);
	assert.doesNotMatch(screen, /price_centavos, 0\)/);
});

test('the Price sort option is hidden without the income permission', async () => {
	const table = await read('src/lib/shared/ReportTable.svelte');
	assert.match(table, /showPrice \? sortOptions : sortOptions\.filter\(\(option\) => option\.value !== 'price'\)/);
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
