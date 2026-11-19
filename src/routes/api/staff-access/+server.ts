import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler, RequestEvent } from './$types';

export const prerender = false;

async function staffClient(event: RequestEvent) {
	const supabase = requestSupabase(event);
	const { data: { user }, error: failure } = await supabase.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Account access is temporarily unavailable.');
	if (!user) error(401, 'Sign in to manage staff access.');
	return supabase;
}

function reportError(failure: { code: string }) {
	switch (failure.code) {
		case '42501': error(403, 'Staff access requires a verified Owner or Superadmin with the matching grants.');
		case 'P0002': error(404, 'Ask this person to create and verify a HERCO account first.');
		case '40001': error(409, 'This staff account changed. Reload before saving.');
		case '22023': error(400, 'Check the staff account and select the matching page for each action.');
		default: error(503, 'Staff access is temporarily unavailable. Try again.');
	}
}

export const GET: RequestHandler = async (event) => {
	const supabase = await staffClient(event);
	const { data, error: failure } = await supabase.rpc('herco_staff_access');
	if (failure) reportError(failure);
	return json(data);
};

function isGrantList(value: unknown, limit: number): value is string[] {
	return Array.isArray(value) && value.length <= limit &&
		value.every(grant => typeof grant === 'string' && grant.length > 0 && grant.length <= 60);
}

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	const editing = typeof body?.targetId === 'string';
	const uuid = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/iu;
	const email = typeof body?.email === 'string' ? body.email.trim() : '';
	if (
		!body || !['staff', 'admin', 'restricted_admin'].includes(body.role) ||
		typeof body.enabled !== 'boolean' || !isGrantList(body.pages, 20) || !isGrantList(body.actions, 40) ||
		(editing
			? !uuid.test(body.targetId) || !Number.isInteger(body.revision) || body.revision < 1 || body.revision > 2147483647
			: !email || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(email))
	) error(400, 'Check the staff account and permissions.');

	const supabase = await staffClient(event);
	const { error: failure } = await supabase.rpc('herco_save_staff_access', {
		p_target_id: editing ? body.targetId : null,
		p_email: editing ? null : email,
		p_role: body.role,
		p_enabled: body.enabled,
		p_page_grants: body.pages,
		p_action_grants: body.actions,
		p_expected_revision: editing ? body.revision : null
	});
	if (failure) reportError(failure);
	return new Response(null, { status: 204 });
};
