import assert from 'node:assert/strict';
import { existsSync, readdirSync, statSync } from 'node:fs';
import test from 'node:test';
import { powderShowcase, showcaseCategories } from '../src/lib/shared/powder-showcase.ts';
import { SHOWCASE_PAGE, countByCategory, filterPhotos, shownCount, stepIndex, swipeDelta } from '../src/lib/shared/showcase-gallery.ts';
import { showcaseHome, showcaseTotal } from '../src/lib/shared/showcase-home.ts';

const staticFile = (path) => new URL('../static/' + path, import.meta.url);
const categoryIds = showcaseCategories.map((category) => category.id);

// Showcase revamp (owner request 2026-11-23): every unique shop photo, masonry, filters, viewer.

test('the gallery lists every unique owner photo once, with real text and a known category', () => {
	assert.equal(powderShowcase.length, 91);
	assert.equal(new Set(powderShowcase.map((photo) => photo.slug)).size, powderShowcase.length, 'duplicate slug');
	for (const photo of powderShowcase) {
		assert.match(photo.slug, /^[a-z0-9]+(?:-[a-z0-9]+)*$/, photo.slug);
		assert.ok(categoryIds.includes(photo.category), photo.slug);
		assert.ok(photo.title.trim() && photo.alt.trim(), photo.slug);
		assert.notEqual(photo.alt, photo.title, 'alt text should describe the photo, not repeat the title: ' + photo.slug);
		assert.ok(photo.finish === undefined || photo.finish.trim().length > 0, photo.slug);
		assert.ok(Number.isInteger(photo.w) && Number.isInteger(photo.h) && photo.w >= 100 && photo.h >= 100, photo.slug + ' size');
	}
});

test('every listed photo has both sizes on disk and no unlisted files are shipped', () => {
	const listed = new Set();
	for (const photo of powderShowcase) {
		for (const width of [480, 960]) {
			const name = `${photo.slug}-${width}.webp`;
			listed.add(name);
			assert.ok(existsSync(staticFile('photos/showcase/' + name)), name + ' is missing');
		}
		assert.ok(statSync(staticFile(`photos/showcase/${photo.slug}-480.webp`)).size <= 110 * 1024, photo.slug + '-480 too large');
		assert.ok(statSync(staticFile(`photos/showcase/${photo.slug}-960.webp`)).size <= 320 * 1024, photo.slug + '-960 too large');
	}
	const onDisk = readdirSync(staticFile('photos/showcase/'));
	assert.deepEqual(onDisk.filter((name) => !listed.has(name)), [], 'unlisted files in static/photos/showcase');
});

test('every category has photos and the counts add up', () => {
	const counts = countByCategory(powderShowcase);
	assert.equal(counts.all, powderShowcase.length);
	for (const id of categoryIds) assert.ok(counts[id] > 0, id + ' is empty');
	assert.equal(categoryIds.reduce((sum, id) => sum + counts[id], 0), counts.all);
	assert.deepEqual(countByCategory([]), { all: 0 });
});

test('filters keep the original order and "all" returns a copy', () => {
	const all = filterPhotos(powderShowcase, 'all');
	assert.deepEqual(all, [...powderShowcase]);
	assert.notEqual(all, powderShowcase);
	const parts = filterPhotos(powderShowcase, 'parts');
	assert.ok(parts.every((photo) => photo.category === 'parts'));
	assert.deepEqual(parts, powderShowcase.filter((photo) => photo.category === 'parts'));
	assert.deepEqual(filterPhotos(powderShowcase, 'unknown'), []);
});

test('"Show more" grows by one page and never past the total', () => {
	assert.equal(shownCount(91, 1), SHOWCASE_PAGE);
	assert.equal(shownCount(91, 2), SHOWCASE_PAGE * 2);
	assert.equal(shownCount(91, 99), 91);
	assert.equal(shownCount(10, 1), 10);
	assert.equal(shownCount(0, 1), 0);
	for (const bad of [0, -1, 1.5, Number.NaN]) assert.equal(shownCount(91, bad), SHOWCASE_PAGE, String(bad));
});

test('the viewer wraps from last to first and back', () => {
	assert.equal(stepIndex(0, 1, 5), 1);
	assert.equal(stepIndex(4, 1, 5), 0);
	assert.equal(stepIndex(0, -1, 5), 4);
	assert.equal(stepIndex(0, 1, 1), 0);
	assert.equal(stepIndex(0, 1, 0), -1);
});

test('only a clear sideways swipe changes the photo', () => {
	assert.equal(swipeDelta(-80, 5), 1, 'swipe left = next');
	assert.equal(swipeDelta(80, 5), -1, 'swipe right = previous');
	assert.equal(swipeDelta(30, 0), 0, 'too short');
	assert.equal(swipeDelta(-80, 70), 0, 'mostly vertical scroll');
});

test('the Home strip shows 4 real Showcase photos and the right total', () => {
	assert.equal(showcaseTotal, powderShowcase.length);
	assert.equal(showcaseHome.length, 4);
	for (const item of showcaseHome) {
		const photo = powderShowcase.find((entry) => entry.slug === item.slug);
		assert.ok(photo, item.slug + ' is not in the Showcase list');
		assert.equal(item.title, photo.title);
		assert.equal(item.alt, photo.alt);
	}
});
