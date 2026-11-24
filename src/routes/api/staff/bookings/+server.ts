import { readJsonBody } from '#lib/server/request-body.ts';
import { isVisitHour, parseDateHours } from '#lib/server/schedule-input.ts';
import { error, json, type RequestEvent } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

const dateFormat = /^\d{4}-\d{2}-\d{2}$/;
const idFormat = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;

async function staffClient(event: RequestEvent) {
	const client = requestSupabase(event);
	const { data: { user }, error: failure } = await client.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in to use the staff workspace.');
	if (!user.email_confirmed_at) error(403, 'Confirm your email before using the staff workspace.');
	return client;
}

function reportFailure(code: string): never {
	if (code === '42501') error(403, 'You do not have permission for this staff action.');
	if (code === 'P0002') error(404, 'This booking could not be found.');
	if (code === '23P01') error(409, 'This booking is no longer pending. Refresh the schedule.');
	if (['22007', '22008', '22023', '22P02'].includes(code)) error(400, 'Check the date, time, or note and try again.');
	error(503, 'The staff workspace is temporarily unavailable.');
}

export const GET: RequestHandler = async (event) => {
	if (event.url.searchParams.get('view') === 'requests') {
		const page = Number(event.url.searchParams.get('page') ?? '1');
		if (!Number.isInteger(page) || page < 1 || page > 251) error(400, 'Choose a valid page.');
		const client = await staffClient(event);
		const { data, error: failure } = await client.rpc('herco_staff_booking_change_cards', { skip: (page - 1) * 20 });
		if (failure) reportFailure(failure.code);
		return json({ requests: data.slice(0, 20), hasMore: page < 251 && data.length > 20 });
	}
	const date = event.url.searchParams.get('date') ?? '';
	if (!dateFormat.test(date)) error(400, 'Choose a valid date.');
	const client = await staffClient(event);
	const { data, error: failure } = await client.rpc('herco_staff_booking_day_with_options', { visit_date: date });
	if (failure) reportFailure(failure.code);
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	const client = await staffClient(event);
	if (body?.action === 'share') {
		if (typeof body.bookingId !== 'string' || !idFormat.test(body.bookingId) || typeof body.note !== 'string' ||
			body.note.length > 1000 || typeof body.photos !== 'boolean') error(400, 'Check the customer message and photo choice.');
		const { error: failure } = await client.rpc('herco_share_booking_details', { booking: body.bookingId, shared_note: body.note, share_photos: body.photos });
		if (failure) reportFailure(failure.code);
	} else if (body?.action === 'change') {
		if (typeof body.bookingId !== 'string' || !idFormat.test(body.bookingId) ||
			typeof body.requestId !== 'string' || !idFormat.test(body.requestId) ||
			!['cancel', 'reschedule'].includes(body.kind) ||
			typeof body.originalDate !== 'string' || !dateFormat.test(body.originalDate) ||
			(body.originalHour !== null && !isVisitHour(body.originalHour)) ||
			typeof body.reason !== 'string' || body.reason.length > 500) {
			error(400, 'Check the booking and the requested change.');
		}
		if (body.kind === 'reschedule') {
			if (body.originalHour === null || typeof body.date !== 'string' || !dateFormat.test(body.date) ||
				!isVisitHour(body.hour)) error(400, 'Choose a valid new visit.');
		} else if (body.date != null || body.hour != null) {
			error(400, 'Only rescheduling needs a new date and time.');
		}
		const { error: failure } = await client.rpc('herco_staff_change_booking', {
			booking_id: body.bookingId, request_id: body.requestId, kind: body.kind,
			original_date: body.originalDate, original_hour: body.originalHour, reason: body.reason,
			target_date: body.date ?? null, target_hour: body.hour ?? null
		});
		if (failure?.code === '23P01') error(409, failure.message);
		if (failure?.code === '23505') error(409, 'That visit is no longer available. Choose a different time.');
		if (failure) reportFailure(failure.code);
	} else if (body?.action === 'review') {
		if (typeof body.requestId !== 'string' || !idFormat.test(body.requestId) ||
			!['approved', 'declined'].includes(body.decision)) error(400, 'Check the request and decision.');
		const { error: failure } = await client.rpc('herco_review_booking_change', {
			request_id: body.requestId, decision: body.decision
		});
		if (failure?.code === '23P01') error(409, failure.message);
		if (failure) reportFailure(failure.code);
	} else if (body?.action === 'confirm') {
		if (typeof body.bookingId !== 'string' || !idFormat.test(body.bookingId) ||
			typeof body.note !== 'string' || body.note.length > 500) error(400, 'Check the booking and note.');
		const { error: failure } = await client.rpc('herco_confirm_booking', {
			booking_id: body.bookingId, approval_note: body.note
		});
		if (failure) reportFailure(failure.code);
	} else {
		const dateActions = ['open_date', 'close_date', 'restore_date'];
		const slotActions = ['block_slot', 'unblock_slot'];
		if (typeof body?.date !== 'string' || !dateFormat.test(body.date)) error(400, 'Choose a valid date.');
		if (body.action === 'set_date_hours') {
			const parsed = parseDateHours(body);
			if ('message' in parsed) error(400, parsed.message);
			const { data, error: failure } = await client.rpc('herco_set_date_hours', {
				p_date: body.date, p_open_hour: parsed.value.openHour, p_close_hour: parsed.value.closeHour,
				p_confirm_outside: parsed.value.confirmOutside, p_confirmed_outside: parsed.value.confirmedOutsideCount
			});
			if (failure?.code === '22023' && failure.message === 'That date has passed.') error(400, 'That date has passed.');
			if (failure) reportFailure(failure.code);
			if (data?.saved === false) {
				return json({ code: 'bookings_outside_hours', bookings: data.bookings, outsideCount: data.outsideCount }, { status: 409 });
			}
			return json({ outsideCount: data?.outsideCount ?? 0 });
		}
		if (slotActions.includes(body.action)) {
			if (!isVisitHour(body.hour)) error(400, 'Choose a valid time.');
		} else if (!dateActions.includes(body.action) || body.hour != null) {
			error(400, 'Choose a valid scheduling action.');
		}
		const { error: failure } = await client.rpc('herco_set_availability', {
			visit_date: body.date, change: body.action, visit_hour: body.hour ?? null
		});
		if (failure) reportFailure(failure.code);
	}
	return new Response(null, { status: 204 });
};
