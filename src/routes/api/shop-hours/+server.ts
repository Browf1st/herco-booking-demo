import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import { toShopHours } from '#lib/server/shop-hours.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = async (event) => {
	const { data, error: failure } = await requestSupabase(event).rpc('herco_shop_hours');
	const hours = failure ? null : toShopHours(data);
	if (!hours) error(503, 'Opening hours are temporarily unavailable.');
	// Same answer for everyone, so a short shared cache is safe. Errors stay no-store (hooks.server.ts).
	return json(hours, { headers: { 'cache-control': 'public, max-age=60' } });
};
