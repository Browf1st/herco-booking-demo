import { readdir, readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

const budgets = {
	worker: {
		directory: '.svelte-kit/cloudflare/client',
		// Raised 2026-11-20 when the Worker screens adopted the demo UI (calendar, dialogs, cart);
		// still well under the matching demo budgets below.
		javascript: { index: 60, book: 70, account: 60, 'my-bookings': 72, preview: 60, admin: 85, pricing: 65 },
		styles: { index: 8, book: 9, account: 7, 'my-bookings': 8, preview: 7, admin: 12, pricing: 7 }
	},
	demo: {
		directory: 'build',
		// Admin includes the shared header, which now also carries the role-based staff menu.
		javascript: { index: 76, book: 84, account: 73, 'my-bookings': 87, preview: 72, admin: 124, pricing: 72 },
		styles: { index: 9, book: 11, account: 8, 'my-bookings': 11, preview: 8, admin: 18, pricing: 7 }
	}
};

const photoLimits = {
	'herco-cruiser-480.webp': 95,
	'herco-red-wheels-480.webp': 150,
	'wheel-set-480.webp': 140,
	'wheel-set-720.webp': 280,
	// Home page photos from the owner's colour folder (2026-11-23): powder service card and wheel colours.
	'powder/fire-red-scooter-wheels-480.webp': 60,
	'colours/fire-red-480.webp': 70,
	'colours/fire-pink-480.webp': 70,
	'colours/fire-violet-480.webp': 70,
	'colours/fire-aqua-teal-480.webp': 70,
	'colours/fire-gold-480.webp': 70,
	'colours/chrome-black-480.webp': 70,
	'colours/high-gloss-white-480.webp': 70,
	'colours/miko-silver-480.webp': 70
};
// Showcase gallery (2026-11-23): every file in photos/showcase must stay under these limits (KiB).
// The grid loads the 480 files lazily; the photo viewer loads one 960 file at a time.
const folderPhotoLimits = { showcase: { '-480.webp': 110, '-960.webp': 320 } };
const responsivePhotos = {
	// Home builds Showcase URLs from each photo's folder and slug.
	index: ['herco-cruiser-480.webp', 'powder/fire-red-scooter-wheels-480.webp', 'black-and-red-two-tone-wheel', 'blue-side'],
	preview: ['photos/showcase/', 'black-and-red-two-tone-wheel']
};

const mode = process.argv[2];
const budget = Object.hasOwn(budgets, mode) ? budgets[mode] : undefined;
if (!budget || process.argv.length !== 3) {
	console.error('Usage: node scripts/performance-budget.mjs <worker|demo>. Build that target first.');
	process.exit(2);
}

function initialAssets(html) {
	const assets = new Set();
	for (const match of html.matchAll(/<(?:link|script)\b[^>]*>/gi)) {
		const path = match[0].match(/\b(?:href|src)=["']([^"']+)["']/i)?.[1];
		if (!path || /^(?:[a-z]+:|\/\/)/i.test(path)) continue;
		const built = path.match(/(?:^|\/)(_app\/immutable\/[\w./-]+\.(?:js|css))$/);
		if (built) assets.add(built[1]);
		else if (/^(?:\.\/|\/)?theme\.js$/.test(path)) assets.add('theme.js');
	}
	return assets;
}

const assetsByPath = new Map();
const failures = [];
const kib = (bytes) => (bytes / 1024).toFixed(1);

for (const [route, javascriptLimit] of Object.entries(budget.javascript)) {
	const file = join(budget.directory, route + '.html');
	try {
		const files = initialAssets(await readFile(file, 'utf8'));
		let javascript = 0;
		let styles = 0;
		const missingPhotos = new Set(responsivePhotos[route] ?? []);
		for (const asset of files) {
			if (!assetsByPath.has(asset)) {
				const contents = await readFile(join(budget.directory, asset));
				assetsByPath.set(asset, { contents, gzipBytes: gzipSync(contents).byteLength });
			}
			const { contents, gzipBytes } = assetsByPath.get(asset);
			if (asset.endsWith('.js')) javascript += gzipBytes;
			else styles += gzipBytes;
			for (const photo of missingPhotos) if (contents.includes(photo)) missingPhotos.delete(photo);
		}
		if (![...files].some(asset => asset.startsWith('_app/') && asset.endsWith('.js')) || !styles) {
			throw new Error('No initial app JavaScript or stylesheet references found.');
		}
		const stylesLimit = budget.styles[route];
		console.log(`${route}: JS ${kib(javascript)}/${javascriptLimit} KiB, CSS ${kib(styles)}/${stylesLimit} KiB (gzip)`);
		if (javascript > javascriptLimit * 1024) failures.push(`${route} JavaScript exceeds ${javascriptLimit} KiB.`);
		if (styles > stylesLimit * 1024) failures.push(`${route} CSS exceeds ${stylesLimit} KiB.`);
		for (const photo of missingPhotos) failures.push(`${route} does not reference ${photo} in its initial assets.`);
	} catch (error) {
		failures.push(`${route}: ${error.message}`);
	}
}

for (const [name, limit] of Object.entries(photoLimits)) {
	try {
		const size = (await readFile(join(budget.directory, 'photos', name))).byteLength;
		console.log(`${name}: ${kib(size)}/${limit} KiB`);
		if (size > limit * 1024) failures.push(`${name} exceeds ${limit} KiB.`);
	} catch (error) {
		failures.push(`${name}: ${error.message}`);
	}
}

for (const [folder, limits] of Object.entries(folderPhotoLimits)) {
	try {
		const names = await readdir(join(budget.directory, 'photos', folder));
		let checked = 0;
		let largest = { name: '', size: 0 };
		for (const name of names) {
			const suffix = Object.keys(limits).find((ending) => name.endsWith(ending));
			if (!suffix) { failures.push(`photos/${folder}/${name} has no size limit; use a ${Object.keys(limits).join(' or ')} file.`); continue; }
			const size = (await stat(join(budget.directory, 'photos', folder, name))).size;
			checked++;
			if (size > largest.size) largest = { name, size };
			if (size > limits[suffix] * 1024) failures.push(`photos/${folder}/${name} exceeds ${limits[suffix]} KiB.`);
		}
		if (!checked) failures.push(`photos/${folder} has no photos.`);
		console.log(`photos/${folder}: ${checked} files, largest ${largest.name} ${kib(largest.size)} KiB`);
	} catch (error) {
		failures.push(`photos/${folder}: ${error.message}`);
	}
}

if (failures.length) {
	for (const failure of failures) console.error(failure);
	process.exitCode = 1;
}
