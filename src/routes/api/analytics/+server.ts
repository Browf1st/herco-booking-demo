import { HERCO_GA4_API_SECRET, HERCO_GA4_MEASUREMENT_ID } from '$app/env/private';
import { error, json } from '@sveltejs/kit';
import { requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const cookie = 'herco-analytics';
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const events = new Set(['booking_started', 'service_selected', 'booking_submitted', 'change_request_submitted']);
const configured = () => Boolean(HERCO_GA4_MEASUREMENT_ID?.match(/^G-[A-Z0-9]+$/) && HERCO_GA4_API_SECRET);
const noStore = { 'cache-control': 'private, no-store' };
const empty = () => new Response(null, { status: 204, headers: noStore });

async function readCommand(request: Request) {
	const reader = request.body?.getReader();
	if (!reader) return '';
	const buffer = new Uint8Array(64);
	let length = 0;
	try {
		while (true) {
			const { done, value } = await reader.read();
			if (done) return new TextDecoder().decode(buffer.subarray(0, length));
			if (length + value.byteLength > buffer.byteLength) {
				await reader.cancel().catch(() => {});
				error(400, 'Invalid analytics request.');
			}
			buffer.set(value, length);
			length += value.byteLength;
		}
	} finally {
		reader.releaseLock();
	}
}

export const GET: RequestHandler = (event) => {
	const value = event.cookies.get(cookie) ?? '';
	return json({ enabled: configured(), status: uuid.test(value) ? 'on' : value === 'off' ? 'off' : 'unset' }, { headers: noStore });
};

export const PUT: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const choice = await readCommand(event.request);
	if ((choice !== 'allow' && choice !== 'decline') || (choice === 'allow' && !configured())) {
		error(400, 'Choose your analytics preference.');
	}
	const value = choice === 'allow'
		? (event.cookies.get(cookie) ?? '').match(uuid)?.[0] ?? crypto.randomUUID()
		: 'off';
	event.cookies.set(cookie, value, {
		path: '/', httpOnly: true, sameSite: 'lax', secure: event.url.protocol === 'https:', maxAge: 60 * 60 * 24 * 180
	});
	return empty();
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const clientId = event.cookies.get(cookie) ?? '';
	if (!configured() || !uuid.test(clientId)) return empty();
	const name = await readCommand(event.request);
	if (!events.has(name)) error(400, 'Invalid analytics event.');
	const target = new URL('https://www.google-analytics.com/mp/collect');
	target.searchParams.set('measurement_id', HERCO_GA4_MEASUREMENT_ID!);
	target.searchParams.set('api_secret', HERCO_GA4_API_SECRET!);
	try {
		await event.fetch(target, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				client_id: clientId, consent: { ad_user_data: 'DENIED', ad_personalization: 'DENIED' },
				events: [{ name }]
			}),
			signal: AbortSignal.timeout(2000)
		});
	} catch {
		// Analytics is optional. A delivery failure does not affect the booking.
	}
	return empty();
};
