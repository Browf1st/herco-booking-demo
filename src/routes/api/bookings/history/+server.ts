import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const uuid = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;

// Customer-safe change log for the customer's own booking. Staff names, reasons and notes are never returned.
// Staff use GET /api/staff/booking-history instead.
export const GET: RequestHandler = async event => {
	const booking = event.url.searchParams.get('booking') ?? '';
	if (!uuid.test(booking)) error(400, 'Choose a valid booking.');
	const client = requestSupabase(event);
	const { data: { user }, error: authFailure } = await client.auth.getUser();
	if (authFailure?.status && authFailure.status >= 500) error(503, 'Account access is unavailable.');
	if (!user) error(401, 'Sign in to see your booking history.');
	const { data, error: failure } = await client.rpc('herco_customer_booking_history', { booking });
	if (failure?.code === '42501') error(403, 'Could not find a booking you can access.');
	if (failure?.code === 'P0002') error(404, 'Could not find a booking you can access.');
	if (failure || !data || !Array.isArray(data.entries)) error(503, 'Booking history is temporarily unavailable.');
	return json({ booking_id: data.booking_id, entries: data.entries }, { headers: { 'cache-control': 'private, no-store' } });
};
