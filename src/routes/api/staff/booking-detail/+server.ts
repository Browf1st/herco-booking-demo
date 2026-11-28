import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const uuid = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;

// One booking's full staff record for the "More details" popup (used by the Customers directory).
// Staff only; amounts only with the viewIncome grant, decided in the database.
export const GET: RequestHandler = async event => {
	const booking = event.url.searchParams.get('booking') ?? '';
	if (!uuid.test(booking)) error(400, 'Choose a valid booking.');
	const client = requestSupabase(event);
	const { data: { user }, error: authFailure } = await client.auth.getUser();
	if (authFailure?.status && authFailure.status >= 500) error(503, 'Account access is unavailable.');
	if (!user) error(401, 'Sign in to see booking details.');
	const { data, error: failure } = await client.rpc('herco_staff_booking_detail', { booking });
	if (failure?.code === '42501') error(403, 'Your account cannot see this booking.');
	if (failure?.code === 'P0002') error(404, 'Booking not found.');
	if (failure?.code === '22023') error(400, 'Choose a valid booking.');
	if (failure) error(503, 'Booking details are temporarily unavailable.');
	return json(data, { headers: { 'cache-control': 'private, no-store' } });
};
