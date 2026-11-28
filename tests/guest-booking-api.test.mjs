import assert from 'node:assert/strict';
import { registerHooks } from 'node:module';
import { test } from 'node:test';

const supabase = 'data:text/javascript,' + encodeURIComponent(`
	import { error } from '@sveltejs/kit';
	export const requestSupabase = event => event.client;
	export function requireSameOrigin(event) {
		if (event.request.headers.get('origin') !== event.url.origin) error(403, 'Wrong origin');
	}
`);
const hooks = registerHooks({
	resolve(specifier, context, nextResolve) {
		if (specifier === '#lib/server/supabase.ts') return { url: supabase, shortCircuit: true };
		return nextResolve(specifier, context);
	}
});
// Bare package imports cannot be resolved from a data: module.
const kit = import.meta.resolve('@sveltejs/kit');
const kitHook = registerHooks({
	resolve(specifier, context, nextResolve) {
		return specifier === '@sveltejs/kit' && context.parentURL === supabase
			? { url: kit, shortCircuit: true }
			: nextResolve(specifier, context);
	}
});
const { POST: manual } = await import('../src/routes/api/staff/manual-booking/+server.ts');
hooks.deregister();
kitHook.deregister();

const payload = {
	action: 'book_guest', requestId: '11111111-1111-4111-8111-111111111111',
	name: 'Test Mara Villanueva', bike: 'Test Honda Click', services: ['basic'],
	date: '2026-12-04', hour: 10, plate: ''
};

function request(body, { user = { email_confirmed_at: '2026-01-01' }, failure = null, origin = 'http://herco.test' } = {}) {
	const url = new URL('http://herco.test');
	const calls = [];
	return {
		url, calls,
		request: new Request(url, { method: 'POST', headers: { origin }, body: JSON.stringify(body) }),
		client: {
			auth: { getUser: async () => ({ data: { user }, error: null }) },
			rpc: async (...args) => {
				calls.push(args);
				return { data: { ok: true }, error: failure };
			}
		}
	};
}

test('a staff guest booking accepts a name with no phone or account', async () => {
	const event = request(payload);
	assert.equal((await manual(event)).status, 200);
	const [[rpc, booking]] = event.calls;
	assert.equal(rpc, 'herco_create_staff_guest_booking');
	assert.equal(booking.customer_name, payload.name);
	assert.equal(booking.customer_phone, '');
	assert.equal(booking.customer_email, '');
	assert.equal(booking.walk_in, false);
	assert.equal('customer' in booking, false);
});

test('guest booking validates blank names, phones, slots, walk-ins and permission failures', async () => {
	for (const change of [{ name: '   ' }, { name: 'a'.repeat(121) }, { phone: 12 }, { phone: 'abc' }, { hour: -1 }, { walkIn: true }, { walkIn: 'yes' }, { email: 'not-an-email' }, { email: 5 }, { email: 'a@b.test'.padStart(256, 'x') }]) {
		const event = request({ ...payload, ...change });
		await assert.rejects(() => manual(event), { status: 400 });
		assert.equal(event.calls.length, 0);
	}
	await assert.rejects(() => manual(request(payload, { user: null })), { status: 401 });
	await assert.rejects(() => manual(request(payload, { failure: { code: '42501' } })), { status: 403 });
	const priceChange = await manual(request(payload, { failure: { code: 'P0409' } }));
	assert.equal(priceChange.status, 409);
	assert.equal((await priceChange.json()).code, 'price_changed');
});

test('a guest walk-in sends no hour and an optional trimmed email', async () => {
	const event = request({ ...payload, hour: null, walkIn: true, email: '  mara@example.test ' });
	assert.equal((await manual(event)).status, 200);
	const [[, booking]] = event.calls;
	assert.equal(booking.visit_hour, null);
	assert.equal(booking.walk_in, true);
	assert.equal(booking.customer_email, 'mara@example.test');
	const { date, ...noDate } = payload;
	const undated = request({ ...noDate, hour: null, walkIn: true });
	assert.equal((await manual(undated)).status, 200);
	assert.equal(undated.calls[0][1].visit_date, null);
	await assert.rejects(() => manual(request(noDate)), { status: 400 });
	const blank = request({ ...payload, hour: null, walkIn: true, email: '' });
	assert.equal((await manual(blank)).status, 200);
	assert.equal(blank.calls[0][1].customer_email, '');
});

test('verified manual bookings keep the account-based database path', async () => {
	const event = request({
		...payload, action: 'book', email: 'mara@example.test', phone: '09170000000',
		customerId: '22222222-2222-4222-8222-222222222222'
	});
	await manual(event);
	assert.equal(event.calls[0][0], 'herco_create_staff_booking_configured');
	assert.equal(event.calls[0][1].customer_email, 'mara@example.test');
});
