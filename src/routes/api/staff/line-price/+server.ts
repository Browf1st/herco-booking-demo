import { error, json } from '@sveltejs/kit';
import { readJsonBody } from '#lib/server/request-body.ts';
import { linePriceFailure, parseLinePriceRequest } from '#lib/server/line-price-input.ts';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

// Staff change the price of one service line on a Pending or Booked booking. The database checks the adjustPrices grant.
export const POST: RequestHandler = async event => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	const input = parseLinePriceRequest(body);
	if (!input) error(400, 'Enter a whole-peso price from 0 to 1,000,000 and a reason of up to 200 characters.');
	const client = requestSupabase(event);
	const { data: { user }, error: authFailure } = await client.auth.getUser();
	if (authFailure?.status && authFailure.status >= 500) error(503, 'Account access is unavailable.');
	if (!user) error(401, 'Sign in to change prices.');
	const { data, error: failure } = await client.rpc('herco_staff_set_line_price', {
		booking: input.booking, request_id: input.requestId, service_code: input.service,
		expected_price_centavos: input.expectedCentavos, new_price_centavos: input.centavos, reason: input.reason
	});
	if (failure) {
		const answer = linePriceFailure(failure.code);
		if (answer.code) return json({ code: answer.code, message: answer.message }, { status: answer.status });
		error(answer.status, answer.message);
	}
	return json(data);
};
