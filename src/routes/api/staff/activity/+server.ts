import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = async (event) => {
	const from = event.url.searchParams.get('from') ?? '';
	const through = event.url.searchParams.get('through') ?? '';
	const date = /^\d{4}-\d{2}-\d{2}$/;
	if (!date.test(from) || !date.test(through)) error(400, 'Choose a start and end date.');
	const { data, error: failure } = await requestSupabase(event).rpc('herco_staff_activity', {
		from_date: from, through_date: through
	});
	if (failure?.code === '42501') error(403, 'Activity log access requires Owner permission and MFA.');
	if (failure?.code === '22023' || failure?.code === '22007' || failure?.code === '22008') {
		error(400, 'Choose a date range of up to 31 days.');
	}
	if (failure) error(503, 'The activity log is temporarily unavailable.');
	return json(data);
};
