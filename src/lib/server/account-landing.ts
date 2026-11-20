import { error } from '@sveltejs/kit';
import { parseWorkspaceAccess, workspaceLanding } from '#lib/workspace-navigation.ts';
import type { requestSupabase } from './supabase.ts';

export async function accountLanding(client: ReturnType<typeof requestSupabase>) {
	const { data, error: failure } = await client.rpc('herco_workspace_permissions');
	if (failure) error(503, 'Signed in, but your account navigation could not be loaded. Try again.');
	const access = parseWorkspaceAccess(data);
	if (data !== null && !access) error(503, 'Your account navigation could not be loaded. Try again.');
	return workspaceLanding(access);
}
