import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json, type RequestEvent } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

const idPattern = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;

export const PATCH: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.requestId !== 'string' || !idPattern.test(body.requestId)) error(400, 'Choose a valid request.');
	const client = await customerClient(event);
	const { error: failure } = await client.rpc('herco_withdraw_booking_change', { request_id: body.requestId });
	if (failure?.code === 'P0002') error(404, 'This request could not be found.');
	if (failure?.code === '23P01') error(409, 'The shop already reviewed this request.');
	if (failure) error(503, 'Could not confirm withdrawal. Try again.');
	return new Response(null, { status: 204 });
};

async function customerClient(event: RequestEvent) {
	const client = requestSupabase(event);
	const { data: { user }, error: failure } = await client.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in to manage your change requests.');
	return client;
}

export const GET: RequestHandler = async (event) => {
	const ids = [...new Set(event.url.searchParams.getAll('booking'))];
	if (!ids.length || ids.length > 20 || ids.some(id => !idPattern.test(id))) error(400, 'Choose valid booking references.');
	const client = await customerClient(event);
	const { data, error: failure } = await client.rpc('herco_customer_booking_changes', { booking_ids: ids });
	if (failure) error(503, 'Change requests are temporarily unavailable.');
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.bookingId !== 'string' || !idPattern.test(body.bookingId) ||
		typeof body.submissionId !== 'string' || !idPattern.test(body.submissionId) ||
		!['cancel', 'reschedule'].includes(body.kind) || typeof body.reason !== 'string' || body.reason.length > 500) {
		error(400, 'Check the booking, change type, and reason.');
	}
	if (body.kind === 'reschedule') {
		if (typeof body.date !== 'string' || !datePattern.test(body.date) ||
			!Number.isInteger(body.hour) || body.hour < 9 || body.hour > 16) error(400, 'Choose a valid visit date and time.');
	} else if (body.date != null || body.hour != null) {
		error(400, 'Only a reschedule request needs a new visit time.');
	}
	const client = await customerClient(event);
	const { data, error: failure } = await client.rpc('herco_request_booking_change', {
		booking_id: body.bookingId, submission_id: body.submissionId, kind: body.kind,
		reason: body.reason, target_date: body.date ?? null, target_hour: body.hour ?? null
	});
	if (failure?.code === 'P0002') error(404, 'This booking could not be found.');
	if (failure?.code === '23P01') error(409, failure.message);
	if (failure?.code === '23505') error(409, 'This booking already has a pending request.');
	if (failure && ['22007', '22008', '22023', '22P02'].includes(failure.code)) {
		error(400, 'Check the requested visit and reason.');
	}
	if (failure) error(503, 'Could not save your request. Try again with the same details.');
	return json({ id: data });
};
