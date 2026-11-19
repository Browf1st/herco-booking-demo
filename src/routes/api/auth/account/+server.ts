import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { resolve } from '$app/paths';
import { HERCO_AUTH_EMAIL_ENABLED, HERCO_AUTH_FACEBOOK_ENABLED, HERCO_AUTH_GOOGLE_ENABLED } from '$app/env/private';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

const authProviders = () => ({
	google: HERCO_AUTH_GOOGLE_ENABLED,
	facebook: HERCO_AUTH_FACEBOOK_ENABLED
});

export const GET: RequestHandler = () => json(
	{ email: HERCO_AUTH_EMAIL_ENABLED, providers: authProviders() },
	{ headers: { 'cache-control': 'no-store' } }
);

function validEmail(value: unknown) {
	if (typeof value !== 'string') return null;
	const email = value.trim();
	return email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(email) ? email : null;
}

function passwordValue(value: unknown) {
	if (typeof value !== 'string' || value.length < 8 || value.length > 1024) {
		error(400, 'Use a password with at least eight characters.');
	}
	return value;
}

function reportServiceFailure(failure: { status?: number } | null) {
	if (!failure) return;
	if (failure.status === 429) error(429, 'Too many requests. Please try again later.');
	if (!failure.status || failure.status >= 500) error(503, 'The account service is temporarily unavailable.');
}

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (body?.action === 'oauth') {
		const provider: unknown = body.provider;
		if ((provider !== 'google' && provider !== 'facebook') || !authProviders()[provider]) {
			error(403, 'This sign-in option is unavailable.');
		}
		const callback = new URL(resolve('/api/auth/callback'), event.url);
		const { data, error: failure } = await requestSupabase(event).auth.signInWithOAuth({
			provider, options: { redirectTo: callback.href, skipBrowserRedirect: true }
		});
		reportServiceFailure(failure);
		if (failure || !data.url) error(503, 'Could not start social sign-in.');
		return json({ url: data.url });
	}

	if (!HERCO_AUTH_EMAIL_ENABLED) error(403, 'Email account setup is unavailable.');

	switch (body?.action) {
		case 'signup': {
			const email = validEmail(body.email);
			if (!email) error(400, 'Enter a valid email address.');
			const password = passwordValue(body.password);
			const supabase = requestSupabase(event);
			const { data, error: failure } = await supabase.auth.signUp({ email, password });
			reportServiceFailure(failure);
			if (failure?.code === 'weak_password') error(400, 'Choose a stronger password.');
			if (data.session) {
				await supabase.auth.signOut({ scope: 'local' });
				error(503, 'Email confirmation must be enabled before signup is available.');
			}
			// Supabase may return a registration error for existing accounts. Do not reveal whether the email is registered.
			return json({ accepted: true }, { status: 202 });
		}
		case 'recover': {
			const email = validEmail(body.email);
			if (!email) error(400, 'Enter a valid email address.');
			const { error: failure } = await requestSupabase(event).auth.resetPasswordForEmail(email);
			reportServiceFailure(failure);
			return json({ accepted: true }, { status: 202 });
		}
		case 'confirm':
		case 'reset-password': {
			const email = validEmail(body.email);
			const token = typeof body.token === 'string' ? body.token.trim() : '';
			if (!email || !/^\d{6}$/u.test(token)) error(400, 'Enter your email and the six-digit code.');
			const password = body.action === 'reset-password' ? passwordValue(body.password) : undefined;
			const supabase = requestSupabase(event);
			const { data, error: failure } = await supabase.auth.verifyOtp({
				email, token, type: password ? 'recovery' : 'email'
			});
			reportServiceFailure(failure);
			if (failure || !data.session) error(400, 'This code is invalid or expired. Check the code or request a new one.');
			if (password) {
				const { error: updateFailure } = await supabase.auth.updateUser({ password });
				if (updateFailure) {
					await supabase.auth.signOut({ scope: 'local' });
					const hint = updateFailure.code === 'same_password' ? 'Choose a different password.' : 'Choose a stronger password.';
					error(400, 'The password could not be updated. Request a new code. ' + hint);
				}
			}
			return new Response(null, { status: 204 });
		}
		default:
			error(400, 'Choose an account action.');
	}
};
