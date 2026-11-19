import { PUBLIC_SUPABASE_PUBLISHABLE_KEY, PUBLIC_SUPABASE_URL } from '$app/env/private';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = () => {
	const configured = Boolean(PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_PUBLISHABLE_KEY);
	return json({ status: configured ? 'configured' : 'configuration-required' }, {
		status: configured ? 200 : 503,
		headers: { 'cache-control': 'no-store' }
	});
};
