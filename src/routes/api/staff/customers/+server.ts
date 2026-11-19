import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;

// Use a request body so a customer's email or account ID is not written into URL access logs.
export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (!body || (body.operation !== 'directory' && body.operation !== 'visits')) error(400, 'Unknown customer lookup.');
	const supabase = requestSupabase(event);
	let response;
	if (body.operation === 'directory') {
		const term = typeof body.term === 'string' ? body.term.trim() : null;
		const cursor = body.cursor ?? null;
		if (term === null || term.length > 254 || (term.length > 0 && term.length < 2) ||
			(cursor !== null && (typeof cursor !== 'string' || !uuid.test(cursor)))) {
			error(400, 'Enter at least two name characters or a complete email address.');
		}
		response = await supabase.rpc('herco_staff_customers', { search_term: term, after_customer: cursor });
	} else {
		const { customer, page } = body;
		if (typeof customer !== 'string' || !uuid.test(customer) || typeof page !== 'number' ||
			!Number.isInteger(page) || page < 1 || page > 50) error(400, 'Choose a customer and valid visit page.');
		response = await supabase.rpc('herco_staff_customer_visits', { customer, visit_page: page });
	}
	const { data, error: failure } = response;
	if (failure?.code === '42501' || failure?.code === 'PGRST301') {
		error(403, 'Customer access requires staff permission and MFA.');
	}
	if (failure?.code === '22023') {
		error(400, body.operation === 'directory'
			? 'Enter at least two name characters or a complete email address.'
			: 'Choose a customer and valid visit page.');
	}
	if (failure?.code === 'P0002') error(404, 'Customer not found.');
	if (failure) error(503, 'Customer records are temporarily unavailable.');
	return json(data);
};
