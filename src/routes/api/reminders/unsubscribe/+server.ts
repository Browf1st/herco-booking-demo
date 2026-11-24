import { HERCO_REMINDER_TOKEN_SECRET, HERCO_STORAGE_SECRET_KEY, PUBLIC_SUPABASE_URL } from '$app/env/private';
import { createClient } from '@supabase/supabase-js';
import { error } from '@sveltejs/kit';
import { readJsonBody } from '#lib/server/request-body.ts';
import { parseUnsubscribeBody } from '#lib/server/reminder-input.ts';
import { MIN_SECRET_LENGTH, verifyUnsubscribeToken } from '#lib/server/reminder-token.ts';
import { requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

export const prerender = false;

// Public: the signed token is the only credential. The signature is checked before any database call,
// so forged or expired tokens cost nothing and change nothing. Repeating a valid token is fine.
export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	const parsed = parseUnsubscribeBody(await readJsonBody(event.request));
	if ('message' in parsed) error(400, parsed.message);
	if (!HERCO_REMINDER_TOKEN_SECRET || HERCO_REMINDER_TOKEN_SECRET.length < MIN_SECRET_LENGTH ||
		!PUBLIC_SUPABASE_URL || !HERCO_STORAGE_SECRET_KEY) {
		error(503, 'Reminder settings are temporarily unavailable.');
	}

	const customerId = await verifyUnsubscribeToken(parsed.value.token, HERCO_REMINDER_TOKEN_SECRET);
	if (!customerId) error(400, 'This link doesn’t work any more.');

	const client = createClient(PUBLIC_SUPABASE_URL, HERCO_STORAGE_SECRET_KEY, {
		auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
		global: { fetch: event.fetch }
	});
	const { error: failure } = await client.rpc('herco_unsubscribe_maintenance_reminders', { p_customer: customerId });
	if (failure) error(503, 'Couldn’t save. Try again.');
	return new Response(null, { status: 204 });
};
