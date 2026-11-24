import { error, json, type RequestEvent } from '@sveltejs/kit';
import { readJsonBody } from '#lib/server/request-body.ts';
import { parseReminderSetting } from '#lib/server/reminder-input.ts';
import { requestSupabase, requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

// The signed-in customer's own setting only: the database reads the user from the session (auth.uid()).
async function customerClient(event: RequestEvent) {
	const client = requestSupabase(event);
	const { data: { user }, error: failure } = await client.auth.getUser();
	if (failure?.status && failure.status >= 500) error(503, 'Reminder settings are temporarily unavailable.');
	if (!user) error(401, 'Sign in to change reminder settings.');
	return client;
}

export const GET: RequestHandler = async (event) => {
	const client = await customerClient(event);
	const { data, error: failure } = await client.rpc('herco_get_maintenance_reminders');
	if (failure?.code === '42501') error(401, 'Sign in to change reminder settings.');
	if (failure || typeof data !== 'boolean') error(503, 'Reminder settings are temporarily unavailable.');
	return json({ maintenance: data });
};

export const PUT: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const parsed = parseReminderSetting(await readJsonBody(event.request));
	if ('message' in parsed) error(400, parsed.message);
	const client = await customerClient(event);
	const { data, error: failure } = await client.rpc('herco_set_maintenance_reminders', { p_enabled: parsed.value.maintenance });
	if (failure?.code === '42501') error(401, 'Sign in to change reminder settings.');
	if (failure?.code === '22023') error(400, 'Choose on or off for maintenance reminders.');
	if (failure || typeof data !== 'boolean') error(503, 'Couldn’t save. Try again.');
	return json({ maintenance: data });
};
