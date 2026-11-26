import assert from 'node:assert/strict';
import { existsSync, readFileSync, statSync } from 'node:fs';
import test from 'node:test';
import { nextTabIndex } from '../src/lib/shared/auth-tabs.ts';
import { photos, wheelColours } from '../src/lib/shared/config.ts';

const staticFile = (path) => new URL('../static/' + path, import.meta.url);

// Home page photos (owner request 2026-11-23)

test('every wheel colour has a real name, a unique id and both photo sizes on disk', () => {
	assert.equal(wheelColours.length, 8);
	assert.equal(new Set(wheelColours.map((colour) => colour.id)).size, wheelColours.length);
	for (const colour of wheelColours) {
		assert.ok(colour.name.trim().length > 0, colour.id);
		assert.match(colour.photo, /^photos\/colours\/[a-z-]+-720\.webp$/);
		assert.equal(colour.photoSmall, colour.photo.replace('-720.webp', '-480.webp'));
		for (const path of [colour.photo, colour.photoSmall]) assert.ok(existsSync(staticFile(path)), path + ' is missing');
	}
});

test('the small wheel photos stay light enough for phones', () => {
	for (const colour of wheelColours) assert.ok(statSync(staticFile(colour.photoSmall)).size <= 70 * 1024, colour.photoSmall);
});

test('the powder coating card has both photo sizes on disk', () => {
	for (const path of [photos.powder, photos.powderSmall]) assert.ok(existsSync(staticFile(path)), path + ' is missing');
	assert.ok(statSync(staticFile(photos.powderSmall)).size <= 60 * 1024);
});

// Log in / Sign up tabs

test('arrow keys move between the two tabs and wrap around', () => {
	assert.equal(nextTabIndex('ArrowRight', 0, 2), 1);
	assert.equal(nextTabIndex('ArrowRight', 1, 2), 0);
	assert.equal(nextTabIndex('ArrowLeft', 0, 2), 1);
	assert.equal(nextTabIndex('ArrowLeft', 1, 2), 0);
});

test('Home and End jump to the first and last tab', () => {
	assert.equal(nextTabIndex('Home', 1, 2), 0);
	assert.equal(nextTabIndex('End', 0, 2), 1);
});

test('other keys and an empty tab list do nothing', () => {
	for (const key of ['Enter', ' ', 'Tab', 'a', 'ArrowUp', 'ArrowDown', '']) assert.equal(nextTabIndex(key, 0, 2), null);
	assert.equal(nextTabIndex('ArrowRight', 0, 0), null);
});

// Screen wiring that has no runtime test harness: read the source to guard the agreed layout.

const read = (path) => readFileSync(new URL('../' + path, import.meta.url), 'utf8');

test('reward title and cost share one row in the live Points screen', () => {
	const heading = read('src/lib/shared/RewardHeading.svelte');
	assert.match(heading, /-webkit-line-clamp: 2/);
	assert.match(heading, /grid-template-columns: minmax\(0, 1fr\) auto/);
	for (const page of ['src/lib/live/ServerPoints.svelte']) {
		const source = read(page);
		assert.equal((source.match(/<RewardHeading /g) ?? []).length, 2, page);
		assert.doesNotMatch(source, /<p class="eyebrow">\{reward\.points/, page);
	}
});

test('regression: the sign-in card input style does not resize the code-step digit boxes', () => {
	const shell = read('src/lib/shared/AuthShell.svelte');
	assert.doesNotMatch(shell, /:global\(input:not/);
	assert.match(shell, /:global\(label > input\)/);
	assert.match(shell, /\.auth-link\) \{[^}]*min-height: 44px/);
});

test('the live sign-in card keeps the social buttons and shows the email form straight away', () => {
	const source = read('src/lib/live/ServerAccount.svelte');
	assert.match(source, /onclick=\{\(\) => signInWith\(provider\)\}/);
	assert.doesNotMatch(source, /showForm/);
	assert.doesNotMatch(source, /with Email<\/button>/);
	assert.match(source, /<PasswordField /);
	assert.match(source, /Forgot password\?/);
});
