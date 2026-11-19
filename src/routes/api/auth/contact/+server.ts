import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json, type RequestEvent } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

async function profileClient(event: RequestEvent) {
	const client = requestSupabase(event);
	const { data: { user }, error: failure } = await client.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Your profile is temporarily unavailable.');
	if (!user) error(401, 'Sign in to view your profile.');
	return { client, id: user.id };
}

export const GET: RequestHandler = async (event) => {
	const { client, id } = await profileClient(event);
	const { data, error: failure } = await client.from('herco_customer_profiles')
		.select('display_name,mobile').eq('user_id', id).maybeSingle();
	if (failure) error(503, 'Your profile is temporarily unavailable.');
	return json({ name: data?.display_name ?? '', mobile: data?.mobile ?? '' });
};

export const PUT: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.name !== 'string' || typeof body.mobile !== 'string') error(400, 'Check your contact details.');
	const name = body.name.trim();
	const mobile = body.mobile.trim();
	const validMobile = !mobile || (/^\+?[0-9 ()-]{7,20}$/.test(mobile) && /^\d{7,15}$/.test(mobile.replace(/\D/g, '')));
	if (name.length > 120 || !validMobile) error(400, 'Enter a valid name and mobile number.');
	const { client, id } = await profileClient(event);
	const { error: failure } = await client.from('herco_customer_profiles')
		.upsert({ user_id: id, display_name: name, mobile });
	if (failure) error(503, 'Could not save your profile. Please try again.');
	return json({ name, mobile });
};
