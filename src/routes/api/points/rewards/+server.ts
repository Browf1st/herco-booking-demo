import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';
export const prerender = false;
export const GET: RequestHandler = async event => {
	const { data, error: failure } = await requestSupabase(event).rpc('herco_reward_preview');
	if (failure) error(503, 'Rewards are temporarily unavailable.');
	return json(data);
};
