import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = async (event) => {
	const booking = event.url.searchParams.get('booking') ?? '';
	if (!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(booking)) error(400, 'Choose a valid booking.');
	const supabase = requestSupabase(event);
	const { data: { user }, error: authFailure } = await supabase.auth.getUser();
	if (authFailure?.status && authFailure.status >= 500) error(503, 'Booking activity is temporarily unavailable.');
	if (!user) error(401, 'Sign in to see booking activity.');
	const { data, error: failure } = await supabase.from('herco_booking_events')
		.select('id,kind,to_status,created_at').eq('booking_id', booking)
		.order('id', { ascending: false }).limit(50);
	if (failure) error(503, 'Booking activity is temporarily unavailable.');
	return json({ events: data.toReversed() });
};
