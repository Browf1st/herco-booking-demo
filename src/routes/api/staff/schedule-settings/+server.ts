import { readJsonBody } from '#lib/server/request-body.ts';
import { parseScheduleSettings } from '#lib/server/schedule-input.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

async function staffClient(event: Parameters<RequestHandler>[0]) {
	const client = requestSupabase(event);
	const { data: { user }, error: failure } = await client.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in to use the staff workspace.');
	if (!user.email_confirmed_at) error(403, 'Confirm your email before using the staff workspace.');
	return client;
}

export const GET: RequestHandler = async (event) => {
	const client = await staffClient(event);
	const { data, error: failure } = await client.rpc('herco_staff_schedule_settings');
	if (failure?.code === '42501') error(403, 'You do not have access to the schedule.');
	if (failure || !data) error(503, 'Opening hours are temporarily unavailable.');
	return json(data);
};

export const PUT: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	const parsed = parseScheduleSettings(body);
	if ('message' in parsed) error(400, parsed.message);
	const client = await staffClient(event);
	const { openHour, closeHour, openWeekdays, confirmOutside, version, confirmedOutsideCount } = parsed.value;
	const { data, error: failure } = await client.rpc('herco_set_schedule_settings', {
		p_open_hour: openHour, p_close_hour: closeHour, p_open_weekdays: openWeekdays, p_confirm_outside: confirmOutside,
		p_version: version, p_confirmed_outside: confirmedOutsideCount
	});
	if (failure?.code === '42501') error(403, 'You don’t have permission to change the schedule.');
	if (failure?.code === '22023') error(400, 'Check the opening hours and open days.');
	if (failure || !data) error(503, 'Couldn’t save. Try again.');
	if (data.saved === false && data.code === 'schedule_changed') {
		return json({ code: 'schedule_changed', message: 'Opening hours were changed by someone else. Reload to see the latest.' }, { status: 409 });
	}
	if (data.saved === false) {
		return json({ code: 'bookings_outside_hours', bookings: data.bookings, outsideCount: data.outsideCount }, { status: 409 });
	}
	return json({
		openHour: data.openHour, closeHour: data.closeHour, openWeekdays: data.openWeekdays, outsideCount: data.outsideCount,
		version: data.version
	});
};
