import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.bike !== 'string' || !body.bike.trim() || body.bike.length > 120 ||
		!Array.isArray(body.services) || !body.services.length || body.services.length > 20 ||
		body.services.some((service: unknown) => typeof service !== 'string' || !service || service.length > 64) ||
		(body.coating !== undefined && (!body.coating || typeof body.coating !== 'object' ||
			Array.isArray(body.coating) || JSON.stringify(body.coating).length > 3000))) {
		error(400, 'Check the bike, services, and coating details.');
	}
	const supabase = requestSupabase(event);
	const { data, error: failure } = await supabase.rpc('herco_preview_coating_price', {
		bike: body.bike.trim(), service_codes: body.services, options: body.coating ?? {}
	});
	if (failure?.code === '42501' || failure?.code === 'PGRST301') error(403, 'Verify your email before preparing a booking.');
	if (failure?.code === '22023') error(400, failure.message);
	if (failure) error(503, 'Could not load the estimate. Try again.');
	return json(data);
};
