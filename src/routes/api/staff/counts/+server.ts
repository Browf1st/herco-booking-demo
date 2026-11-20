import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

// Pending booking and change-request totals for the staff Booking menu badges.
export const GET: RequestHandler = async (event) => {
	const { data, error: failure } = await requestSupabase(event).rpc('herco_staff_pending_counts');
	if (failure?.code === '42501' || failure?.code === 'PGRST301') error(403, 'Booking access requires staff permission.');
	if (failure) error(503, 'Booking counts are temporarily unavailable.');
	return json(data);
};
