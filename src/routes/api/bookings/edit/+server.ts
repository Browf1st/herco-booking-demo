import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import { serviceConflict } from '#lib/server/line-price-input.ts';
import { isValidMobile } from '#lib/shared/mobile.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const uuid = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;
const fingerprint = /^[a-f0-9]{32}$/;

function reportFailure(code: string, message: string): never {
	if (code === 'P0002' || code === '42501') error(404, 'Could not find a booking you can access.');
	if (code === '22023') error(400, message);
	error(503, 'The booking is temporarily unavailable.');
}

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.bookingId !== 'string' || !uuid.test(body.bookingId) ||
		typeof body.requestId !== 'string' || !uuid.test(body.requestId) ||
		!Number.isInteger(body.revision) || body.revision < 0 || body.revision > 2147483647 ||
		!Array.isArray(body.services) || !body.services.length || body.services.length > 20 ||
		body.services.some((code: unknown) => typeof code !== 'string' || !code || code.length > 64) ||
		(body.coating !== undefined && (!body.coating || typeof body.coating !== 'object' || Array.isArray(body.coating) || JSON.stringify(body.coating).length > 3000)) ||
		typeof body.bike !== 'string' || !body.bike.trim() || body.bike.length > 120 ||
		typeof body.name !== 'string' || !body.name.trim() || body.name.length > 120 ||
		typeof body.phone !== 'string' || body.phone.length > 40 ||
		typeof body.plate !== 'string' || body.plate.length > 30 ||
		(body.priceFingerprint !== undefined && body.priceFingerprint !== null && (typeof body.priceFingerprint !== 'string' || !fingerprint.test(body.priceFingerprint)))) {
		error(400, 'Check the motorcycle, contact details and selected services.');
	}
	// Mobile is optional on a customer's own booking; if given it must look like a real number.
	if (body.phone.trim() !== '' && !isValidMobile(body.phone)) error(400, 'Enter a valid mobile number, or leave it blank.');

	const client = requestSupabase(event);
	const { data: { user }, error: authFailure } = await client.auth.getUser();
	if (authFailure?.status && authFailure.status >= 500) error(503, 'Account access is unavailable.');
	if (!user) error(401, 'Sign in to edit your booking.');

	const { data, error: failure } = await client.rpc('herco_edit_booking_configured', {
		booking_id: body.bookingId, request_id: body.requestId, expected_revision: body.revision,
		new_bike: body.bike, new_name: body.name, new_phone: body.phone, new_plate: body.plate,
		service_codes: body.services, options: body.coating ?? {},
		expected_price_fingerprint: body.priceFingerprint ?? null
	});
	if (failure?.code === 'P0423') {
		// The message is written by our own database function.
		return json({ code: 'shop_priced', message: failure.message }, { status: 409 });
	}
	if (failure?.code === '40001') {
		const { data: current } = await client.rpc('herco_booked_services', { booking_id: body.bookingId });
		return json(serviceConflict(current?.canEdit), { status: 409 });
	}
	if (failure) reportFailure(failure.code, failure.message);
	return json(data);
};
