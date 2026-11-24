import { error, json } from '@sveltejs/kit';
import { readJsonBody } from '#lib/server/request-body.ts';
import { parseRecordsRequest } from '#lib/server/records-input.ts';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';
export const prerender = false;
export const POST: RequestHandler = async event => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	const query = parseRecordsRequest(body);
	if (!query) error(400, 'Check the booking filters.');
	const { data, error: failure } = await requestSupabase(event).rpc('herco_staff_booking_records', {
		from_date: query.from, through_date: query.through, search_term: query.search,
		status_filter: query.status, source_filter: query.source, record_page: query.page, report_mode: query.report,
		sort_by: query.sort
	});
	if (failure?.code === '42501') error(403, 'Your account does not have access to these records.');
	if (failure && ['22023', '22007', '22008'].includes(failure.code)) error(400, 'Choose valid filters and a date range of up to 366 days.');
	if (failure) error(503, 'Booking records are temporarily unavailable.');
	return json(data);
};
