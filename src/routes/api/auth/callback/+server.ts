import { redirect } from '@sveltejs/kit';
import { resolve } from '$app/paths';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = async (event) => {
	const code = event.url.searchParams.get('code');
	const account = new URL(resolve('/account'), event.url).pathname;
	if (!code || code.length > 1024 || event.url.searchParams.has('error')) {
		event.setHeaders({ 'cache-control': 'private, no-store', 'referrer-policy': 'no-referrer' });
		redirect(303, account + '?auth=retry');
	}
	event.setHeaders({ 'referrer-policy': 'no-referrer' });
	const { error: failure } = await requestSupabase(event).auth.exchangeCodeForSession(code);
	redirect(303, failure ? account + '?auth=retry' : account);
};
