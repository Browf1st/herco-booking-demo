import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = async (event) => {
	const from = event.url.searchParams.get('from') ?? '';
	const to = event.url.searchParams.get('to') ?? '';
	const dateFormat = /^\d{4}-\d{2}-\d{2}$/;
	if (!dateFormat.test(from) || !dateFormat.test(to)) error(400, 'Enter a start and end date.');

	const { data, error: failure } = await requestSupabase(event).rpc('herco_availability', {
		from_date: from, to_date: to
	});
	if (failure) {
		if (failure.code === '22007' || failure.code === '22008' || failure.code === '22023') {
			error(400, 'Choose valid dates within the next 21 days.');
		}
		error(503, 'Availability is temporarily unavailable.');
	}
	return json(data);
};
