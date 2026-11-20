import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

const idPattern = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;
const emailPattern = /^[^\s@]+@[^\s@]+$/;

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.email !== 'string' || body.email.length > 254 || !emailPattern.test(body.email.trim())) {
		error(400, 'Enter the customer’s complete email address.');
	}
	const client = requestSupabase(event);
	const { data: { user }, error: authFailure } = await client.auth.getUser();
	if (authFailure?.status && authFailure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in with your staff account.');
	if (!user.email_confirmed_at) error(403, 'Confirm your email before using the staff workspace.');

	if (body.action === 'lookup') {
		const { data, error: failure } = await client.rpc('herco_lookup_booking_customer', { customer_email: body.email });
		if (failure?.code === '42501') error(403, 'You do not have permission to create bookings for customers.');
		if (failure) error(503, 'Could not check the customer’s email. Try again.');
		if (!data) error(404, 'No unique verified account matched that email.');
		return json(data);
	}

	if (body.action !== 'book' || typeof body.customerId !== 'string' || !idPattern.test(body.customerId) ||
		typeof body.requestId !== 'string' || !idPattern.test(body.requestId) ||
		typeof body.date !== 'string' || !datePattern.test(body.date) ||
		(body.walkIn === true ? body.hour !== null : !Number.isInteger(body.hour) || body.hour < 9 || body.hour > 16) ||
		!Array.isArray(body.services) || !body.services.length || body.services.length > 20 ||
		body.services.some((service: unknown) => typeof service !== 'string' || !service || service.length > 64) ||
		typeof body.bike !== 'string' || body.bike.length > 120 ||
		typeof body.name !== 'string' || body.name.length > 120 ||
		typeof body.phone !== 'string' || body.phone.length > 40 ||
		typeof body.plate !== 'string' || body.plate.length > 30 ||
		(body.coating !== undefined && (!body.coating || typeof body.coating !== 'object' || Array.isArray(body.coating) || JSON.stringify(body.coating).length > 3000))) {
		error(400, 'Check the customer, services, and visit details.');
	}

	const { data, error: failure } = await client.rpc('herco_create_staff_booking_configured', {
		customer: body.customerId, customer_email: body.email, request_id: body.requestId,
		visit_date: body.date, visit_hour: body.hour, service_codes: body.services,
		bike: body.bike, customer_name: body.name, customer_phone: body.phone, plate_number: body.plate,
		options: body.coating ?? {}, expected_price_fingerprint: body.priceFingerprint ?? null, walk_in: body.walkIn === true
	});
	if (failure?.code === '42501') error(403, 'You do not have permission to create bookings for customers.');
	if (failure?.code === 'P0002') error(404, 'The verified account no longer matches. Search for the email again.');
	if (failure?.code === 'P0409') return json({ code: 'price_changed', message: 'Service prices changed. Review the updated estimate.' }, { status: 409 });
	if (failure && ['23P01', '23505'].includes(failure.code)) error(409, 'The appointment is no longer available. Choose another slot.');
	if (failure && ['22007', '22008', '22023', '22P02'].includes(failure.code)) error(400, failure.message);
	if (failure) error(503, 'Could not save the booking. Retry with the same details.');
	return json(data);
};
