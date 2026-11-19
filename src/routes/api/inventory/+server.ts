import { readJsonBody } from '#lib/server/request-body.ts';
import { error, json } from '@sveltejs/kit';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;

export const GET: RequestHandler = async (event) => {
	const { data, error: failure } = await requestSupabase(event).rpc('herco_inventory');
	if (failure?.code === '42501') error(403, 'Inventory requires staff permission and MFA.');
	if (failure) error(503, 'Inventory is temporarily unavailable.');
	return json(data);
};

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const body = await readJsonBody(event.request);
	if (!body || typeof body.requestId !== 'string' || !uuid.test(body.requestId) ||
		typeof body.stockId !== 'string' || !uuid.test(body.stockId) ||
		!['create', 'edit', 'move'].includes(body.operation) ||
		!body.details || typeof body.details !== 'object' || Array.isArray(body.details) ||
		JSON.stringify(body.details).length > 3000) error(400, 'Check your inventory details.');
	const { data, error: failure } = await requestSupabase(event).rpc('herco_write_inventory', {
		request_id: body.requestId, operation: body.operation, stock_id: body.stockId, details: body.details
	});
	if (failure?.code === '42501') error(403, 'Inventory requires staff permission and MFA.');
	if (failure?.code === '40001') error(409, 'The item changed. Reload inventory before editing again.');
	if (failure?.code === '23505') error(409, 'An item with this name already exists.');
	if (failure?.code === '23514') error(409, 'This change would put stock outside the allowed range.');
	if (failure?.code === '22023' || failure?.code === '22P02' || failure?.code === '22003') {
		error(400, 'Check your inventory details.');
	}
	if (failure) error(503, 'Could not confirm the inventory update. Please try again.');
	return json(data);
};
