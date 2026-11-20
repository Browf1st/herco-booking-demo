import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;

export const GET: RequestHandler = async (event) => {
	const search = event.url.searchParams.get('search') ?? '';
	const member = event.url.searchParams.get('member');
	if (search.length > 254 || (member && !uuid.test(member))) error(400, 'Check the selected customer.');
	const { data, error: failure } = await requestSupabase(event).rpc('herco_staff_points_workspace', { search_term: search, selected_member: member });
	if (failure?.code === '42501') error(403, 'Staff permission are required.');
	if (failure) error(503, 'The points workspace is temporarily unavailable.');
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	const supabase = requestSupabase(event);
	let result;
	if (body?.action === 'adjust' && uuid.test(body.member) && uuid.test(body.requestId) &&
		Number.isSafeInteger(body.delta) && typeof body.reason === 'string' && body.reason.length <= 300) {
		result = await supabase.rpc('herco_adjust_points', {
			member: body.member, delta: body.delta, reason: body.reason, request_id: body.requestId
		});
	} else if ((body?.action === 'approve' || body?.action === 'claim') && uuid.test(body.receipt)) {
		result = await supabase.rpc('herco_review_point_receipt', {
			receipt: body.receipt, decision: body.action
		});
	} else if (body?.action === 'saveReward' && uuid.test(body.id) &&
		typeof body.label === 'string' && body.label.length <= 120 && Number.isSafeInteger(body.cost) &&
		typeof body.enabled === 'boolean') {
		if (typeof body.scope !== 'string' || body.scope.length > 200) error(400, 'Check the reward scope.');
		result = await supabase.rpc('herco_save_reward_details', {
			reward_id: body.id, reward_label: body.label, reward_scope: body.scope, points_cost: body.cost, active: body.enabled
		});
	} else {
		error(400, 'Check the submitted points details.');
	}
	if (result.error?.code === '42501') error(403, 'Staff permission are required.');
	if (result.error?.code === '23514') error(409, 'Check the current balance or approval status.');
	if (result.error?.code === '22023' || result.error?.code === '23503') error(400, 'Check the member or reward details.');
	if (result.error) error(503, 'Could not confirm this update. Please try again.');
	return json({ saved: true });
};
