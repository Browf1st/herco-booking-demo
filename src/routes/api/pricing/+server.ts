import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

const identifier = /^[a-z0-9][a-z0-9-]{0,63}$/;
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const integer = (value: unknown, min: number, max: number): value is number =>
	typeof value === 'number' && Number.isInteger(value) && value >= min && value <= max;
const maximumInteger = 2147483647;

export const GET: RequestHandler = async (event) => {
	const { data, error: failure } = await requestSupabase(event).rpc('herco_pricing');
	if (failure?.code === '42501' || failure?.code === 'PGRST301') {
		error(403, 'Pricing requires staff permission.');
	}
	if (failure) error(503, 'Pricing is temporarily unavailable.');
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (!body || typeof body.requestId !== 'string' || !uuid.test(body.requestId) ||
		!integer(body.revision, 0, maximumInteger) ||
		typeof body.code !== 'string' || !identifier.test(body.code) ||
		typeof body.label !== 'string' || !body.label.trim() || body.label.trim().length > 120 ||
		typeof body.enabled !== 'boolean' ||
		(body.operation !== 'service' && body.operation !== 'promotion')) {
		error(400, 'Check the pricing details.');
	}

	const supabase = requestSupabase(event);
	const common = {
		request_id: body.requestId,
		expected_revision: body.revision,
		is_enabled: body.enabled
	};
	let result;
	if (body.operation === 'service') {
		const quote = body.quoteRequired === true;
		const max = body.maxCentavos ?? null;
		if (!integer(body.priceCentavos, 0, maximumInteger) ||
			(body.enabled && !quote && body.priceCentavos === 0) ||
			(quote && (body.priceCentavos !== 0 || max !== null)) ||
			(max !== null && !integer(max, body.priceCentavos + 1, maximumInteger)) ||
			!Array.isArray(body.days) || body.days.length < 1 || body.days.length > 7 ||
			body.days.some((day: unknown) => !integer(day, 0, 6))) {
			error(400, 'Check the service price and appointment days.');
		}
		result = await supabase.rpc('herco_save_catalog_service', {
			...common,
			service_code: body.code,
			service_label: body.label,
			base_price_centavos: body.priceCentavos,
			visit_days: body.days,
			maximum_centavos: max,
			needs_quote: quote
		});
	} else {
		if (body.revision === 0 || !integer(body.discountBps, 0, 10000) ||
			(body.enabled && body.discountBps === 0)) error(400, 'Check the promotion discount.');
		result = await supabase.rpc('herco_save_booking_promotion', {
			...common,
			promotion_code: body.code,
			display_label: body.label,
			discount_bps: body.discountBps
		});
	}
	const { data, error: failure } = result;
	if (failure?.code === '42501' || failure?.code === 'PGRST301') {
		error(403, 'You need the relevant pricing permission.');
	}
	if (failure?.code === '40001' || failure?.code === '23505') {
		error(409, 'Pricing changed. Reload pricing before editing again.');
	}
	if (failure?.code === '22023' || failure?.code === '23514') error(400, 'Check the pricing details.');
	if (failure) error(503, 'The save could not be confirmed. Retry the same change.');
	return json(data);
};
