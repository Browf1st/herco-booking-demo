import { error, json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = async (event) => {
	const { data, error: failure } = await requestSupabase(event).rpc('herco_workspace_permissions');
	if (failure?.code === '42501' || (!failure && !data)) error(403, 'Verify your staff session.');
	if (failure) error(503, 'Staff permissions are temporarily unavailable.');
	return json(data);
};
