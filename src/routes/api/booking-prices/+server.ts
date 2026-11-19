import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const uuid = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;

function fail(failure: { code: string; message: string } | null) {
	if (!failure) return;
	if (failure.code === '42501') error(403, 'Price corrections require staff permission and MFA.');
	if (failure.code === 'P0002') error(404, 'Booking not found.');
	if (failure.code === '40001' || failure.code === '23514') error(409, failure.message);
	if (failure.code === '22023') error(400, failure.message);
	error(503, 'Booking prices are temporarily unavailable. Retry using the same details.');
}

export const GET: RequestHandler = async (event) => {
	const booking = event.url.searchParams.get('booking') ?? '';
	if (!uuid.test(booking)) error(400, 'Choose a valid booking.');
	const { data, error: failure } = await requestSupabase(event).rpc('herco_booking_prices', { booking });
	fail(failure);
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.booking !== 'string' || !uuid.test(body.booking) ||
		typeof body.requestId !== 'string' || !uuid.test(body.requestId) ||
		!Number.isInteger(body.revision) || body.revision < 0 ||
		typeof body.service !== 'string' || !body.service || body.service.length > 100 ||
		!Number.isSafeInteger(body.centavos) || body.centavos < 0 || body.centavos > 99999999999 ||
		typeof body.reason !== 'string' || !body.reason.trim() || body.reason.length > 300) {
		error(400, 'Enter an exact price and a reason.');
	}
	const { data, error: failure } = await requestSupabase(event).rpc('herco_correct_booking_price', {
		booking: body.booking, expected_revision: body.revision, request_id: body.requestId,
		service_code: body.service, price_centavos: body.centavos, reason: body.reason
	});
	fail(failure);
	return json(data);
};
