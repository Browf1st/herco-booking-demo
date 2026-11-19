import { readJsonBody } from '#lib/server/request-body.ts';
import { createClient } from '@supabase/supabase-js';
import { HERCO_STORAGE_SECRET_KEY, PUBLIC_SUPABASE_URL } from '$app/env/private';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const maxBytes = 4 * 1024 * 1024;
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const bucket = 'herco-completion';

function storageClient(fetch: typeof globalThis.fetch) {
	if (!PUBLIC_SUPABASE_URL || !HERCO_STORAGE_SECRET_KEY) error(503, 'Private photo storage is temporarily unavailable.');
	return createClient(PUBLIC_SUPABASE_URL, HERCO_STORAGE_SECRET_KEY, {
		auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
		global: { fetch }
	}).storage.from(bucket);
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
	const booking = event.url.searchParams.get('booking') ?? '';
	const photo = event.url.searchParams.get('photo');
	if (!uuid.test(booking)) error(400, 'Choose a valid booking.');
	const { data: photos, error: failure } = await requestSupabase(event).rpc('herco_completion_photos', { booking });
	if (failure?.code === '42501') error(403, 'Completion evidence requires staff permission and MFA.');
	if (failure || !Array.isArray(photos)) error(503, 'Completion evidence is temporarily unavailable.');
	if (photo === null) return json({ count: photos.length });
	if (!/^[0-2]$/.test(photo) || !photos[Number(photo)]) error(404, 'Photo not found.');
	const path: string = photos[Number(photo)];
	const { data, error: downloadFailure } = await storageClient(event.fetch).download(path);
	if (downloadFailure || !data) error(503, 'This photo is temporarily unavailable.');
	const type = path.endsWith('.jpg') ? 'image/jpeg' : path.endsWith('.png') ? 'image/png' : 'image/webp';
	return new Response(data, { headers: { 'content-type': type, 'x-content-type-options': 'nosniff' } });
};

export const PUT: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const booking = event.url.searchParams.get('booking') ?? '';
	if (!uuid.test(booking)) error(400, 'Choose a valid booking.');
	const supabase = requestSupabase(event);
	const { data: prefix, error: failure } = await supabase.rpc('herco_completion_upload_target', { booking });
	if (failure?.code === '42501') error(403, 'Completion requires staff permission and MFA.');
	if (failure?.code === '22023') error(409, 'This booking doesn’t accept completion photos.');
	if (failure || typeof prefix !== 'string' || !PUBLIC_SUPABASE_URL || !HERCO_STORAGE_SECRET_KEY) {
		error(503, 'Private photo storage is temporarily unavailable.');
	}
	const bytes = await readPhoto(event.request);
	const { type, extension } = photoType(bytes);
	const path = prefix + crypto.randomUUID() + '.' + extension;
	const { error: uploadFailure } = await storageClient(event.fetch).upload(path, bytes, {
		contentType: type, upsert: false
	});
	if (uploadFailure) error(503, 'Could not save this photo. Please try again.');
	return json({ path }, { status: 201 });
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.booking !== 'string' || !uuid.test(body.booking) ||
		!Number.isSafeInteger(body.priceCentavos) || body.priceCentavos < 0 ||
		!Array.isArray(body.photos) || body.photos.length < 1 || body.photos.length > 3 ||
		body.photos.some((photo: unknown) => typeof photo !== 'string' || photo.length > 125) ||
		typeof body.note !== 'string' || body.note.length > 500) {
		error(400, 'Enter a final price and upload one to three photos.');
	}
	const { data, error: failure } = await requestSupabase(event).rpc('herco_complete_booking', {
		booking: body.booking, price_centavos: body.priceCentavos, photos: body.photos, completion_note: body.note
	});
	if (failure?.code === '42501') error(403, failure.message === 'Changing the final charge requires price adjustment permission.'
		? 'Enter the finalized service total or ask someone with price adjustment permission to update it.'
		: 'Completion requires staff permission and MFA.');
	if (failure?.code === '22023') error(400, 'Check the booking, final price, and uploaded photos.');
	if (failure?.code === '23514') error(409, 'Check the booking status and finalize all service prices.');
	if (failure) error(503, 'Could not confirm completion. Please retry with the same details.');
	return json({ completedAt: data });
};
