import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';
export const prerender = false;
export const GET: RequestHandler = async event => {
	const from = event.url.searchParams.get('from') ?? '';
	const through = event.url.searchParams.get('through') ?? '';
	if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(through)) error(400, 'Choose valid calendar dates.');
	const { data, error: failure } = await requestSupabase(event).rpc('herco_staff_calendar', { from_date: from, through_date: through });
	if (failure?.code === '42501') error(403, 'Your account cannot access the booking calendar.');
	if (failure?.code === '22023') error(400, 'Choose up to 63 calendar dates.');
	if (failure) error(503, 'The booking calendar is temporarily unavailable.');
	return json(data);
};
