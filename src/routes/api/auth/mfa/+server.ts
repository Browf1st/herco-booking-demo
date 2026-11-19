import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json, type RequestEvent } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

async function staffSession(event: RequestEvent) {
	const supabase = requestSupabase(event);
	const { data: { user }, error: failure } = await supabase.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in first.');
	const { data: staff, error: lookupFailure } = await supabase.rpc('herco_may_enroll_staff_mfa');
	if (lookupFailure) error(503, 'Could not check staff access. Try again.');
	return { supabase, staff: staff === true && Boolean(user.email_confirmed_at), factors: user.factors ?? [] };
}

function handleMfaFailure(failure: { status?: number } | null, message: string) {
	if (!failure) return;
	if (failure.status === 429) error(429, 'Too many attempts. Wait a moment and try again.');
	if (!failure.status || failure.status >= 500) error(503, 'Authenticator setup is temporarily unavailable.');
	error(400, message);
}

export const GET: RequestHandler = async (event) => {
	const { supabase, staff, factors } = await staffSession(event);
	if (!staff) return json({ staff: false });

	const { data, error: failure } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
	if (failure || !data) error(503, 'Could not check your sign-in verification.');
	return json({
		staff: true,
		verified: data.currentLevel === 'aal2',
		needsExistingVerification: factors.some(factor => factor.status === 'verified'),
		factors: factors.filter(factor => factor.factor_type === 'totp' && factor.status === 'verified')
			.map(factor => ({ id: factor.id, name: factor.friendly_name ?? 'Authenticator' }))
	});
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const { supabase, staff, factors } = await staffSession(event);
	if (!staff) error(403, 'Authenticator setup is available to verified staff accounts.');
	const body = await readJsonBody(event.request);

	if (body?.action === 'enroll') {
		if (factors.some(factor => factor.status === 'verified')) {
			error(409, 'Verify with your existing authenticator.');
		}
		// Starting again replaces an abandoned setup. Verified factors are never changed here.
		for (const factor of factors.filter(item => item.factor_type === 'totp' && item.status === 'unverified')) {
			const { error: failure } = await supabase.auth.mfa.unenroll({ factorId: factor.id });
			handleMfaFailure(failure, 'Could not restart authenticator setup. Try again.');
		}
		const { data, error: failure } = await supabase.auth.mfa.enroll({
			factorType: 'totp', issuer: 'HERCO', friendlyName: 'HERCO Authenticator'
		});
		handleMfaFailure(failure, 'Could not start authenticator setup. Try again.');
		const prefix = 'data:image/svg+xml;utf-8,';
		if (!data || !data.totp.qr_code.startsWith(prefix)) error(503, 'Could not load the authenticator QR code.');
		return json({
			factorId: data.id,
			qrCode: 'data:image/svg+xml,' + encodeURIComponent(data.totp.qr_code.slice(prefix.length)),
			secret: data.totp.secret
		});
	}
	if (body?.action === 'confirm-enrollment') {
		if (
			typeof body.code !== 'string' || !/^\d{6}$/u.test(body.code) ||
			!factors.some(factor => factor.id === body.factorId && factor.factor_type === 'totp' && factor.status === 'unverified')
		) error(400, 'Enter the six-digit code for this authenticator setup.');
		const { error: failure } = await supabase.auth.mfa.challengeAndVerify({ factorId: body.factorId, code: body.code });
		handleMfaFailure(failure, 'That code could not be verified. Try a new code.');
		return new Response(null, { status: 204 });
	}
	error(400, 'Choose an authenticator action.');
};
