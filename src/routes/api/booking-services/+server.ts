import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json, type RequestEvent } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import { serviceConflict } from '#lib/server/line-price-input.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const uuid = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;

async function clientFor(event: RequestEvent) {
	const client = requestSupabase(event);
	const { data: { user }, error: failure } = await client.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Account access is unavailable.');
	if (!user) error(401, 'Sign in to see booking services.');
	return client;
}

function reportFailure(code: string, message: string): never {
	if (code === 'P0002' || code === '42501') error(404, 'Could not find a booking you can access.');
	if (code === '40001') error(409, message);
	if (code === '22023') error(400, message);
	error(503, 'Booking services are temporarily unavailable.');
}

export const GET: RequestHandler = async (event) => {
	const id = event.url.searchParams.get('booking') ?? '';
	if (!uuid.test(id)) error(400, 'Choose a valid booking.');
	const client = await clientFor(event);
	const { data, error: failure } = await client.rpc('herco_booked_services', { booking_id: id });
	if (failure) reportFailure(failure.code, failure.message);
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.bookingId !== 'string' || !uuid.test(body.bookingId) ||
		typeof body.requestId !== 'string' || !uuid.test(body.requestId) ||
		!Number.isInteger(body.revision) || body.revision < 0 || body.revision > 2147483647 ||
		!Array.isArray(body.services) || !body.services.length || body.services.length > 20 ||
		body.services.some((code: unknown) => typeof code !== 'string' || !code || code.length > 64) ||
		(body.coating !== undefined && (!body.coating || typeof body.coating !== 'object' || Array.isArray(body.coating) || JSON.stringify(body.coating).length > 3000))) {
		error(400, 'Check the booking and selected services.');
	}
	const client = await clientFor(event);
	const { data, error: failure } = await client.rpc(body.coating ? 'herco_save_booked_services_configured' : 'herco_save_booked_services', {
		booking_id: body.bookingId, request_id: body.requestId,
		expected_revision: body.revision, service_codes: body.services,
		...(body.coating ? { options: body.coating, expected_price_fingerprint: body.priceFingerprint ?? null } : {})
	});
	if (failure?.code === 'P0423') {
		// Staff changed a price: the customer can no longer edit services. The message is written by our own database function.
		return json({ code: 'shop_priced', message: failure.message }, { status: 409 });
	}
	if (failure?.code === '40001') {
		// Say which kind of conflict it is: the booking is closed to edits, or it changed since the caller loaded it.
		const { data: current } = await client.rpc('herco_booked_services', { booking_id: body.bookingId });
		return json(serviceConflict(current?.canEdit), { status: 409 });
	}
	if (failure) reportFailure(failure.code, failure.message);
	return json(data);
};
