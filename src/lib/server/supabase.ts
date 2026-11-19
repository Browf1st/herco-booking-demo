import { createServerClient } from '@supabase/ssr';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_PUBLISHABLE_KEY } from '$app/env/private';
import { error, type RequestEvent } from '@sveltejs/kit';

export function requestSupabase(event: RequestEvent) {
	const projectUrl = PUBLIC_SUPABASE_URL;
	const key = PUBLIC_SUPABASE_PUBLISHABLE_KEY;
	if (!projectUrl || !key) error(503, 'The HERCO backend is not configured.');

	event.setHeaders({ 'cache-control': 'private, no-store' });
	return createServerClient(projectUrl, key, {
		global: { fetch: event.fetch },
		cookieOptions: { httpOnly: true, sameSite: 'lax', secure: event.url.protocol === 'https:' },
		cookies: {
			getAll: () => event.cookies.getAll(),
			setAll: (cookies) => {
				for (const { name, value, options } of cookies) {
					event.cookies.set(name, value, { ...options, path: '/' });
				}
			}
		}
	});
}

export function requireSameOrigin(event: RequestEvent) {
	if (event.request.headers.get('origin') !== event.url.origin) {
		error(403, 'Submit this request from HERCO.');
	}
}
