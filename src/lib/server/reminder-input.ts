// Request checks for the F-017 reminder routes (kept free of SvelteKit imports so unit tests can load them).

type Parsed<T> = { value: T } | { message: string };

/** POST /api/reminders/unsubscribe body: { token }. The signature is checked later, with the secret. */
export function parseUnsubscribeBody(body: unknown): Parsed<{ token: string }> {
	const token = (body as { token?: unknown } | null)?.token;
	if (typeof token !== 'string' || !token.trim() || token.length > 200) {
		return { message: 'This link doesn’t work any more.' };
	}
	return { value: { token: token.trim() } };
}

/** PUT /api/account/reminders body: { maintenance: boolean }. Only a real boolean is accepted. */
export function parseReminderSetting(body: unknown): Parsed<{ maintenance: boolean }> {
	const maintenance = (body as { maintenance?: unknown } | null)?.maintenance;
	if (typeof maintenance !== 'boolean') return { message: 'Choose on or off for maintenance reminders.' };
	return { value: { maintenance } };
}
