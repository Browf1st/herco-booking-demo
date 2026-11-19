import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json, type RequestEvent } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

async function verifiedFactors(event: RequestEvent) {
	const client = requestSupabase(event);
	const { data: { user }, error: failure } = await client.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in first.');
	const factors = (user.factors ?? []).filter(factor => factor.factor_type === 'totp' && factor.status === 'verified');
	return { client, factors };
}

export const GET: RequestHandler = async (event) => {
	const { factors } = await verifiedFactors(event);
	return json(factors.map(factor => ({ id: factor.id, name: factor.friendly_name })));
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const { client, factors } = await verifiedFactors(event);
	const body = await readJsonBody(event.request);
	if (!factors.some(factor => factor.id === body?.factorId) || typeof body.code !== 'string' ||
		!/^\d{6}$/.test(body.code)) error(400, 'Enter a six-digit code for your authenticator.');
	const { error: failure } = await client.auth.mfa.challengeAndVerify({ factorId: body.factorId, code: body.code });
	if (failure?.status === 429) error(429, 'Too many attempts. Wait a moment and try again.');
	if (failure?.status && failure.status >= 500) error(503, 'Verification is temporarily unavailable.');
	if (failure) error(400, 'That code could not be verified. Try a new code.');
	return new Response(null, { status: 204 });
};
