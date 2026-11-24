import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL('../' + path, import.meta.url), 'utf8');

test('the home page step section is titled "How booking works" without repeating it in the eyebrow', async () => {
	const page = await read('src/routes/+page.svelte');
	assert.match(page, /<h2>How booking works<\/h2>/);
	assert.doesNotMatch(page, /No chat\. No waiting\./);
	assert.doesNotMatch(page, /<p class="eyebrow">02 \/ How booking works<\/p>/);
});

test('the footer no longer links to Privacy preferences (the page itself stays)', async () => {
	const layout = await read('src/routes/+layout.svelte');
	assert.doesNotMatch(layout, /Privacy preferences/);
	assert.match(await read('src/routes/privacy-preferences/+page.svelte'), /Privacy preferences/);
});

test('the Activity log Apply dates button uses the red primary button', async () => {
	const page = await read('src/routes/activity-log/+page.svelte');
	assert.match(page, /<button class="btn sm" disabled=\{loading\}><ActionIcon name="calendar" \/>/);
});
