import { error, json } from '@sveltejs/kit';
import { readJsonBody } from '#lib/server/request-body.ts';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';
export const prerender = false;
export const POST: RequestHandler = async event => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.from !== 'string' || typeof body.through !== 'string' ||
		!(body.from === '' && body.through === '' || /^\d{4}-\d{2}-\d{2}$/.test(body.from) && /^\d{4}-\d{2}-\d{2}$/.test(body.through)) ||
		typeof body.search !== 'string' || body.search.length > 254 ||
		!['all', 'pending', 'confirmed', 'done', 'cancelled'].includes(body.status) ||
		!['all', 'online', 'walk-in'].includes(body.source) || !Number.isInteger(body.page) || body.page < 1 || body.page > 500 ||
		typeof body.report !== 'boolean') error(400, 'Check the booking filters.');
	const { data, error: failure } = await requestSupabase(event).rpc('herco_staff_booking_records', {
		from_date: body.from || null, through_date: body.through || null, search_term: body.search,
		status_filter: body.status, source_filter: body.source, record_page: body.page, report_mode: body.report
	});
	if (failure?.code === '42501') error(403, 'Your account does not have access to these records.');
	if (failure && ['22023', '22007', '22008'].includes(failure.code)) error(400, 'Choose valid filters and a date range of up to 366 days.');
	if (failure) error(503, 'Booking records are temporarily unavailable.');
	return json(data);
};
