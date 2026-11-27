import { createClient } from '@supabase/supabase-js';
import { HERCO_STORAGE_SECRET_KEY, PUBLIC_SUPABASE_URL } from '$app/env/private';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const maxBytes = 4 * 1024 * 1024;
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
// PUBLIC bucket for colour swatches. Never the private herco-completion bucket.
const bucket = 'herco-swatches';
const types: Record<string, string> = { jpg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };

function storageClient(fetch: typeof globalThis.fetch) {
	if (!PUBLIC_SUPABASE_URL || !HERCO_STORAGE_SECRET_KEY) error(503, 'Swatch photo storage is temporarily unavailable.');
	return createClient(PUBLIC_SUPABASE_URL, HERCO_STORAGE_SECRET_KEY, {
		auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
		global: { fetch }
	}).storage.from(bucket);
}

function entryId(url: URL) {
	const entry = url.searchParams.get('entry') ?? '';
	if (!uuid.test(entry)) error(400, 'Choose a valid colour.');
	return entry.toLowerCase();
}

async function readPhoto(request: Request) {
	if (Number(request.headers.get('content-length')) > maxBytes) error(413, 'Choose a photo up to 4 MB.');
	const reader = request.body?.getReader();
	if (!reader) error(400, 'Choose a photo.');
	const buffer = new Uint8Array(maxBytes);
	let length = 0;
	while (true) {
		const { value, done } = await reader.read();
		if (done) break;
		if (length + value.byteLength > maxBytes) {
			await reader.cancel().catch(() => {});
			error(413, 'Choose a photo up to 4 MB.');
		}
		buffer.set(value, length);
		length += value.byteLength;
	}
	return buffer.subarray(0, length);
}

function photoType(bytes: Uint8Array) {
	const starts = (header: number[]) => header.every((byte, index) => bytes[index] === byte);
	if (starts([255, 216, 255])) return { extension: 'jpg', type: 'image/jpeg' };
	if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return { extension: 'png', type: 'image/png' };
	if (starts([82, 73, 70, 70]) && [87, 69, 66, 80].every((byte, index) => bytes[index + 8] === byte)) {
		return { extension: 'webp', type: 'image/webp' };
	}
	error(400, 'Choose a JPEG, PNG, or WebP photo.');
}

export const GET: RequestHandler = async (event) => {
	const entry = entryId(event.url);
	const storage = storageClient(event.fetch);
	// Only the fixed entry/ folder of the swatch bucket is ever listed or read.
	const { data: files, error: listFailure } = await storage.list('entry', { search: entry, limit: 10 });
	if (listFailure) error(503, 'This photo is temporarily unavailable.');
	const found = (files ?? [])
		.map((file) => ({ file, extension: file.name.startsWith(entry + '.') ? file.name.slice(entry.length + 1) : '' }))
		.filter((item) => item.extension in types)
		.sort((a, b) => String(b.file.updated_at ?? '').localeCompare(String(a.file.updated_at ?? '')))[0];
	if (!found) error(404, 'No photo for this colour.');
	const { data, error: downloadFailure } = await storage.download('entry/' + entry + '.' + found.extension);
	if (downloadFailure || !data) error(503, 'This photo is temporarily unavailable.');
	return new Response(data, {
		headers: {
			'content-type': types[found.extension],
			'x-content-type-options': 'nosniff',
			'cache-control': 'public, max-age=300'
		}
	});
};

export const PUT: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const entry = entryId(event.url);
	const { data: prefix, error: failure } = await requestSupabase(event).rpc('herco_pricing_swatch_target', { entry });
	if (failure?.code === '42501') error(403, 'Pricing permission is required.');
	if (failure?.code === '22023') error(400, 'Save the colour before adding a photo.');
	if (failure || typeof prefix !== 'string' || !prefix.startsWith('entry/')) {
		error(503, 'Swatch photo storage is temporarily unavailable.');
	}
	const bytes = await readPhoto(event.request);
	const { type, extension } = photoType(bytes);
	const path = prefix + '.' + extension;
	const { error: uploadFailure } = await storageClient(event.fetch).upload(path, bytes, {
		contentType: type, upsert: true
	});
	if (uploadFailure) error(503, 'Could not save this photo. Please try again.');
	return json({ path }, { status: 201 });
};
