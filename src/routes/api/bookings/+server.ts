import { readJsonBody } from '#lib/server/request-body.ts';
import { isVisitHour } from '#lib/server/schedule-input.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import { isValidMobile } from '#lib/shared/mobile.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = async (event) => {
	const pageSize = 20;
	const page = Number(event.url.searchParams.get('page') ?? '1');
	if (!Number.isSafeInteger(page) || page < 1 || page > 500) error(400, 'Invalid page number.');
	const offset = (page - 1) * pageSize;
	const supabase = requestSupabase(event);
	const { data: { user }, error: authFailure } = await supabase.auth.getUser();
	if (authFailure?.status && authFailure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in to view your bookings.');

	const { data, error: failure } = await supabase
		.from('herco_bookings')
		.select('id,reference_no,visit_date,visit_hour,bike,status,original_services,original_total_centavos,current_services,current_total_centavos,coating_options,current_coating_options,created_at')
		.eq('customer_id', user.id)
		.order('created_at', { ascending: false })
		.order('id', { ascending: false })
		.range(offset, offset + pageSize);
	if (failure) error(503, 'Your bookings are temporarily unavailable.');
	const bookings = data.slice(0, pageSize);
	if (!bookings.length) return json({ bookings, hasMore: false });
	const { data: events, error: eventFailure } = await supabase.from('herco_booking_events')
		.select('booking_id,to_status,created_at').in('booking_id', bookings.map(booking => booking.id))
		.in('to_status', ['confirmed', 'done', 'cancelled']).order('id', { ascending: true }).limit(500);
	if (eventFailure) error(503, 'Booking history is temporarily unavailable.');
	return json({ bookings: bookings.map(booking => ({ ...booking,
		approved_at: events.find(event => event.booking_id === booking.id && event.to_status === 'confirmed')?.created_at ?? null,
		completed_at: events.find(event => event.booking_id === booking.id && event.to_status === 'done')?.created_at ?? null,
		cancelled_at: events.find(event => event.booking_id === booking.id && event.to_status === 'cancelled')?.created_at ?? null
	})), hasMore: data.length > pageSize });
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (
		typeof body?.requestId !== 'string' ||
		typeof body.date !== 'string' ||
		!isVisitHour(body.hour) ||
		!Array.isArray(body.services) ||
		!body.services.length ||
		body.services.length > 20 ||
		body.services.some((service: unknown) => typeof service !== 'string' || service.length > 64) ||
		typeof body.bike !== 'string' ||
		typeof body.name !== 'string' ||
		typeof body.phone !== 'string' ||
		(body.plate !== undefined && typeof body.plate !== 'string') ||
		(body.coating !== undefined && (!body.coating || typeof body.coating !== 'object' ||
			Array.isArray(body.coating) || JSON.stringify(body.coating).length > 3000)) ||
		(body.priceFingerprint !== undefined && (typeof body.priceFingerprint !== 'string' || !/^[a-f0-9]{32}$/.test(body.priceFingerprint)))
	) error(400, 'Check the visit, selected services, and contact details.');
	// Mobile is optional on a customer's own booking; if given it must look like a real number.
	if (body.phone.trim() !== '' && !isValidMobile(body.phone)) error(400, 'Enter a valid mobile number, or leave it blank.');

	const supabase = requestSupabase(event);
	const { data: { user } } = await supabase.auth.getUser();
	if (!user) error(401, 'Sign in before booking.');

	const { data, error: failure } = await supabase.rpc('herco_create_booking_configured', {
		request_id: body.requestId,
		visit_date: body.date,
		visit_hour: body.hour,
		service_codes: body.services,
		bike: body.bike,
		customer_name: body.name,
		customer_phone: body.phone,
		plate_number: body.plate ?? '',
		options: body.coating ?? {},
		expected_price_fingerprint: body.priceFingerprint ?? null
	}).single<{ id: string; status: string; original_total_centavos: number;
		original_services: { quote_required?: boolean; max_centavos?: number | null }[] }>();
	if (failure) {
		switch (failure.code) {
			case 'P0409':
				return json({ code: 'price_changed', message: 'Service prices changed. Review the new estimate before submitting again.' }, { status: 409 });
			case '23P01':
			case '23505':
				error(409, 'That appointment time is unavailable. Choose another slot.');
			case '42501':
				error(403, 'Verify your email before booking.');
			case '22023':
			case '22007':
			case '22008':
			case '22P02':
				error(400, 'Check the visit, selected services, coating details, and contact information.');
			default:
				error(503, 'Booking is temporarily unavailable. Retry using the same request ID.');
		}
	}
	return json({ id: data.id, status: data.status, totalCentavos: data.original_total_centavos,
		estimateOpen: data.original_services.some(service => service.quote_required || service.max_centavos != null) });
};
