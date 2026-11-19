import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestEvent, RequestHandler } from './$types';

export const prerender = false;
const bookingFormat = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/iu;

async function intakeClient(event: RequestEvent) {
	const supabase = requestSupabase(event);
	const { data: { user }, error: failure } = await supabase.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in to open this intake.');
	return supabase;
}

function reportFailure(code: string): never {
	switch (code) {
		case '42501': error(403, 'You need a verified HERCO account and permission for this intake action.');
		case 'P0002': error(404, 'This booking is unavailable to your account.');
		case '23P01': error(409, 'This intake is no longer open for that action. Reload the booking.');
		case '22023': error(400, 'Review the form, acknowledge it, and use the full name shown on the booking.');
		default: error(503, 'Walk-in intake is temporarily unavailable. Try again.');
	}
}

export const GET: RequestHandler = async (event) => {
	const booking = event.url.searchParams.get('booking') ?? '';
	if (!bookingFormat.test(booking)) error(400, 'Enter the booking reference.');
	const supabase = await intakeClient(event);
	const { data, error: failure } = await supabase.rpc('herco_walk_in_intake', { p_booking_id: booking });
	if (failure) reportFailure(failure.code);
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (
		typeof body?.bookingId !== 'string' || !bookingFormat.test(body.bookingId) ||
		typeof body.formVersion !== 'string' || body.formVersion.length < 1 || body.formVersion.length > 60
	) error(400, 'Check the booking reference and form version.');
	const supabase = await intakeClient(event);
	const args = { p_booking_id: body.bookingId, p_form_version: body.formVersion };

	if (body.action === 'request') {
		const { error: failure } = await supabase.rpc('herco_request_walk_in_intake', args);
		if (failure) reportFailure(failure.code);
	} else if (body.action === 'sign') {
		if (typeof body.name !== 'string' || !body.name.trim() || body.name.length > 120 || body.acknowledged !== true) {
			error(400, 'Review the form, acknowledge it, and type your full name.');
		}
		const { error: failure } = await supabase.rpc('herco_sign_walk_in_intake', {
			...args, p_name: body.name.trim(), p_acknowledged: true
		});
		if (failure) reportFailure(failure.code);
	} else error(400, 'Choose an intake action.');
	return new Response(null, { status: 204 });
};
