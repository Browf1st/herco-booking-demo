import { error, json } from '@sveltejs/kit';
import { readJsonBody } from '#lib/server/request-body.ts';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	const surface = body?.surface;
	const name = body?.name ?? null;
	const query = body?.q ?? '';
	const page = body?.page;
	if ((surface !== 'customers' && surface !== 'history') ||
		(name !== null && (typeof name !== 'string' || !name.trim() || name.length > 120)) ||
		typeof query !== 'string' || query.length > 120 ||
		!Number.isInteger(page) || page < 1 || page > 2_147_483_647 ||
		(surface === 'history' && name === null)) {
		error(400, 'Choose a valid booking name and page.');
	}

	const { data, error: failure } = await requestSupabase(event).rpc('herco_staff_booking_name_groups', {
		p_surface: surface, p_query: query, p_page: page, p_name: name
	});
	if (failure?.code === '42501' || failure?.code === 'PGRST301') error(403, 'Your account does not have access to these records.');
	if (failure?.code === '22023') error(400, 'Choose a valid booking name and page.');
	if (failure) error(503, 'Booking groups are temporarily unavailable.');
	return json(data);
};
