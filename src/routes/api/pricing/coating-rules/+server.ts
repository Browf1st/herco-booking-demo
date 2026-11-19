import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const uuid = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;
const signedIntegerMax = 2147483647;
const nonnegativeInt = (value: unknown): value is number =>
	typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= signedIntegerMax;

export const GET: RequestHandler = async (event) => {
	const { data, error: failure } = await requestSupabase(event).rpc('herco_coating_rules');
	if (failure?.code === '42501' || failure?.code === 'PGRST301') error(403, 'Pricing requires staff permission and MFA.');
	if (failure) error(503, 'Coating rules are temporarily unavailable.');
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (typeof body?.requestId !== 'string' || !uuid.test(body.requestId) ||
		(body.id !== null && (typeof body.id !== 'string' || !uuid.test(body.id))) ||
		!nonnegativeInt(body.revision) || ((body.id === null) !== (body.revision === 0)) ||
		!['ceramic', 'wheel-colour'].includes(body.service) || typeof body.bike !== 'string' || body.bike.trim().length > 120 ||
		typeof body.options !== 'object' || body.options === null || Array.isArray(body.options) ||
		!nonnegativeInt(body.minimumCentavos) ||
		(body.maximumCentavos !== null && (!nonnegativeInt(body.maximumCentavos) || body.maximumCentavos <= body.minimumCentavos)) ||
		typeof body.quoteRequired !== 'boolean' || typeof body.enabled !== 'boolean' ||
		(body.quoteRequired && (body.minimumCentavos !== 0 || body.maximumCentavos !== null))) {
		error(400, 'Check the coating rule details and prices.');
	}
	const { data, error: failure } = await requestSupabase(event).rpc('herco_save_coating_rule', {
		request_id: body.requestId, rule_id: body.id, expected_revision: body.revision,
		service: body.service, bike: body.bike, options: body.options, minimum_centavos: body.minimumCentavos,
		maximum_centavos: body.maximumCentavos, quote_required: body.quoteRequired, is_enabled: body.enabled
	});
	if (failure?.code === '42501' || failure?.code === 'PGRST301') error(403, 'Changing coating prices requires permission and MFA.');
	if (failure?.code === '40001') error(409, 'This coating rule changed. Reload coating rules before editing again.');
	if (failure?.code === '23505') error(409, 'A rule already matches that bike and configuration. Edit that rule instead.');
	if (failure?.code === '22023' || failure?.code === '23514') error(400, failure.message);
	if (failure) error(503, 'The save could not be confirmed. Retry the same change.');
	return json(data);
};
