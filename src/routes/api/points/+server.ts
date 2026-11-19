import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json, type RequestEvent } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

async function signedIn(event: RequestEvent) {
	const supabase = requestSupabase(event);
	const { data, error: failure } = await supabase.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!data.user) error(401, 'Sign in to see your HERCO Points.');
	return supabase;
}

export const GET: RequestHandler = async (event) => {
	const supabase = await signedIn(event);
	const { data, error: failure } = await supabase.rpc('herco_my_points');
	if (failure) error(503, 'Your HERCO Points are temporarily unavailable.');
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
	if (typeof body?.rewardId !== 'string' || !uuid.test(body.rewardId) ||
		typeof body.requestId !== 'string' || !uuid.test(body.requestId)) {
		error(400, 'Choose a reward.');
	}
	const supabase = await signedIn(event);
	const { data, error: failure } = await supabase.rpc('herco_redeem_points', {
		reward_id: body.rewardId,
		request_id: body.requestId
	});
	if (failure?.code === '23514') error(409, 'You need more HERCO Points for this reward.');
	if (failure?.code === '22023') error(400, 'This redemption request is no longer available.');
	if (failure?.code === '42501') error(403, 'Verify your email to redeem rewards.');
	if (failure) error(503, 'Could not confirm your redemption. Try again.');
	return json({ id: data });
};
