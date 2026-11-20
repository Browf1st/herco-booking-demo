import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';
import { accountLanding } from '#lib/server/account-landing.ts';

export const prerender = false;

export const GET: RequestHandler = async (event) => {
	const { data: { user }, error: failure } = await requestSupabase(event).auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in to continue.');
	return json({ id: user.id, email: user.email ?? '' });
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.email !== 'string' || typeof body.password !== 'string') {
		error(400, 'Enter your email and password.');
	}
	const email = body.email.trim();
	if (!email || email.length > 254 || !body.password || body.password.length > 1024) {
		error(400, 'Enter a valid email and password.');
	}
	const supabase = requestSupabase(event);
	const { data, error: failure } = await supabase.auth.signInWithPassword({ email, password: body.password });
	if (failure || !data.user) {
		if (failure?.code === 'email_not_confirmed') {
			return json({ code: 'email_confirmation_required', message: 'Confirm your email to sign in.' }, { status: 403 });
		}
		if (failure?.status === 429) error(429, 'Too many sign-in attempts. Try again later.');
		if (failure?.status && failure.status >= 500) error(503, 'Sign-in is temporarily unavailable.');
		error(401, 'Sign-in failed. Check your email and password.');
	}
	return json({ id: data.user.id, redirectTo: await accountLanding(supabase) });
};

export const DELETE: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const supabase = requestSupabase(event);
	const { error: failure } = await supabase.auth.signOut({ scope: 'local' });
	if (failure) error(503, 'Could not sign out. Try again.');
	return new Response(null, { status: 204 });
};
