import type { Handle } from '@sveltejs/kit/hooks';

export const handle: Handle = async ({ event, resolve }) => {
	const response = await resolve(event);
	// SvelteKit may return an immutable redirect or proxy response.
	const headers = new Headers(response.headers);
	headers.append('content-security-policy', "frame-ancestors 'none'");
	headers.set('x-frame-options', 'DENY');
	headers.set('x-content-type-options', 'nosniff');
	headers.set('permissions-policy', 'camera=(self), geolocation=(), microphone=()');
	if (!headers.has('referrer-policy')) {
		headers.set('referrer-policy', 'strict-origin-when-cross-origin');
	}

	// This also covers authentication/validation errors before a route sets
	// its own policy. A cookie-setting response can never be shared.
	const isApiPath = (path: string | null) => path === '/api' || path?.startsWith('/api/');
	const api = isApiPath(event.route.id) || isApiPath(event.url.pathname);
	if (headers.has('set-cookie') || (api && (response.status >= 400 || !headers.has('cache-control')))) {
		headers.set('cache-control', 'private, no-store');
	}

	return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
};
