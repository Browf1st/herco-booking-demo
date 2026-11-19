import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = async (event) => {
	const from = event.url.searchParams.get('from') ?? '';
	const to = event.url.searchParams.get('to') ?? '';
	const date = /^\d{4}-\d{2}-\d{2}$/;
	if (!date.test(from) || !date.test(to)) error(400, 'Choose a start and end date.');
	const { data, error: failure } = await requestSupabase(event).rpc('herco_booking_report', {
		from_date: from, to_date: to
	});
	if (failure?.code === '42501') error(403, 'Reports require staff permission and MFA.');
	if (failure?.code === '22023' || failure?.code === '22007' || failure?.code === '22008') {
		error(400, 'Choose a valid date range of up to 366 days.');
	}
	if (failure) error(503, 'Reports are temporarily unavailable.');
	return json(data);
};
