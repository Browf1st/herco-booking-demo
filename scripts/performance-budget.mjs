import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

const budgets = {
	worker: {
		directory: '.svelte-kit/cloudflare/client',
		javascript: { index: 60, book: 65, account: 60, 'my-bookings': 65, preview: 60, admin: 65, pricing: 65 },
		styles: { index: 8, book: 7, account: 7, 'my-bookings': 7, preview: 7, admin: 7, pricing: 7 }
	},
	demo: {
		directory: 'build',
		javascript: { index: 76, book: 84, account: 73, 'my-bookings': 87, preview: 72, admin: 120, pricing: 72 },
		styles: { index: 9, book: 11, account: 8, 'my-bookings': 11, preview: 8, admin: 17, pricing: 7 }
	}
};

const photoLimits = {
	'herco-cruiser-480.webp': 95,
	'herco-red-wheels-480.webp': 150,
	'wheel-set-480.webp': 140,
	'wheel-set-720.webp': 280
};
const responsivePhotos = {
	index: ['herco-cruiser-480.webp', 'herco-red-wheels-480.webp'],
	preview: ['wheel-set-480.webp', 'wheel-set-720.webp']
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

if (failures.length) {
	for (const failure of failures) console.error(failure);
	process.exitCode = 1;
}
