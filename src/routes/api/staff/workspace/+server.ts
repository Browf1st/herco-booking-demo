import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = async (event) => {
	const supabase = requestSupabase(event);
	const { data: { user }, error: authFailure } = await supabase.auth.getUser();
	if (authFailure?.status && authFailure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in with your staff account.');
	if (!user.email_confirmed_at) error(403, 'Confirm your email before opening the staff workspace.');
	const { data, error: failure } = await supabase.rpc('herco_workspace_permissions');
	if (failure?.code === '42501' || (!failure && !data)) error(403, 'Your account does not have staff access.');
	if (failure) error(503, 'Staff permissions are temporarily unavailable.');
	return json(data);
};
