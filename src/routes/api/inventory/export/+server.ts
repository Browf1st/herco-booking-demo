import { error } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;
const columns = {
	stock: ['name', 'category', 'unit', 'quantity', 'minimum', 'supplier', 'storage_location', 'unit_cost', 'billing_rate', 'capacity'],
	movements: ['recorded_at_ph', 'name', 'unit', 'operation', 'before_quantity', 'after_quantity', 'reason', 'actor_id']
};

function cell(value: unknown) {
	if (value == null) return '';
	if (typeof value === 'number') return String(value);
	const text = String(value);
	const safe = /^[\s\uFEFF]*[=+\-@]/.test(text) || /^[\t\r\n]/.test(text) ? "'" + text : text;
	return '"' + safe.replaceAll('"', '""') + '"';
}

export const GET: RequestHandler = async (event) => {
	const kind = event.url.searchParams.get('kind');
	if (kind !== 'stock' && kind !== 'movements') error(400, 'Choose a valid export.');
	const from = event.url.searchParams.get('from');
	const through = event.url.searchParams.get('through');
	const date = /^\d{4}-\d{2}-\d{2}$/;
	if (kind === 'movements' && (!from || !through || !date.test(from) || !date.test(through))) {
		error(400, 'Choose a start and end date.');
	}
	const { data, error: failure } = await requestSupabase(event).rpc('herco_inventory_export', {
		export_kind: kind, from_date: kind === 'movements' ? from : null, through_date: kind === 'movements' ? through : null
	});
	if (failure?.code === '42501') error(403, 'Inventory exports require staff permission.');
	if (failure?.code === '22023' || failure?.code === '22007' || failure?.code === '22008') error(400, failure.message);
	if (failure || !Array.isArray(data)) error(503, 'Could not export inventory. Please try again.');
	const header = columns[kind];
	return new Response('\uFEFF' + [header.join(','), ...data.map(row => header.map(column => cell(row[column])).join(','))]
		.join('\r\n') + '\r\n', {
		headers: { 'content-type': 'text/csv; charset=utf-8', 'content-disposition': 'attachment; filename="herco-inventory-' + kind + '.csv"' }
	});
};
