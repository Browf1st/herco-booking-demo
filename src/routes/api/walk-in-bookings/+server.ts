import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json, type RequestEvent } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const uuid = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;

async function customerClient(event: RequestEvent) {
	const supabase = requestSupabase(event);
	const { data: { user }, error: failure } = await supabase.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in to use the walk-in form.');
	return supabase;
}

export const GET: RequestHandler = async (event) => {
	const client = await customerClient(event);
	const { data, error: failure } = await client.rpc('herco_walk_in_booking_form');
	if (failure?.code === '42501') error(403, 'Verify your email to view the walk-in form.');
	if (failure) error(503, 'The walk-in form is temporarily unavailable.');
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.requestId !== 'string' || !uuid.test(body.requestId) ||
		typeof body.date !== 'string' || !datePattern.test(body.date) ||
		!Array.isArray(body.services) || !body.services.length || body.services.length > 20 ||
		body.services.some((service: unknown) => typeof service !== 'string' || !service || service.length > 64) ||
		typeof body.bike !== 'string' || body.bike.length > 120 || typeof body.name !== 'string' || body.name.length > 120 ||
		typeof body.phone !== 'string' || body.phone.length > 40 || typeof body.plate !== 'string' || body.plate.length > 30 ||
		typeof body.formVersion !== 'string' || !body.formVersion || body.formVersion.length > 60 ||
		typeof body.signerName !== 'string' || !body.signerName || body.signerName.length > 120 ||
		body.acknowledged !== true || (body.coating !== undefined && (!body.coating || typeof body.coating !== 'object' ||
			Array.isArray(body.coating) || JSON.stringify(body.coating).length > 3000)) ||
		(body.priceFingerprint !== undefined && (typeof body.priceFingerprint !== 'string' || !/^[a-f0-9]{32}$/.test(body.priceFingerprint)))) {
		error(400, 'Check your contact and coating details and sign the walk-in form.');
	}

	const client = await customerClient(event);
	const { data, error: failure } = await client.rpc('herco_create_walk_in_booking_configured', {
		p_request_id: body.requestId, p_date: body.date, p_service_codes: body.services, p_bike: body.bike,
		p_name: body.name, p_phone: body.phone, p_plate: body.plate, p_form_version: body.formVersion,
		p_signer_name: body.signerName, p_acknowledged: body.acknowledged, p_options: body.coating ?? {},
		p_expected_price_fingerprint: body.priceFingerprint ?? null
	});
	if (failure?.code === 'P0409') {
		return json({ code: 'price_changed', message: 'Service prices changed. Review the new estimate before submitting again.' }, { status: 409 });
	}
	if (failure?.code === '42501') error(403, 'Verify your email before booking.');
	if (failure?.code === '23P01') error(409, failure.message);
	if (failure && ['22007', '22008', '22023', '22P02'].includes(failure.code)) error(400, failure.message);
	if (failure) error(503, 'Could not save the walk-in. Retry with the same details.');
	return json(data);
};
