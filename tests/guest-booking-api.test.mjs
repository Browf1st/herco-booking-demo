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
const { POST: groups } = await import('../src/routes/api/staff/booking-name-groups/+server.ts');
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
	assert.equal('customer_email' in booking, false);
	assert.equal('customer' in booking, false);
});

test('guest booking validates blank names, phones, slots, walk-ins and permission failures', async () => {
	for (const change of [{ name: '   ' }, { name: 'a'.repeat(121) }, { phone: 12 }, { phone: 'abc' }, { hour: -1 }, { walkIn: true }]) {
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

test('verified manual bookings keep the account-based database path', async () => {
	const event = request({
		...payload, action: 'book', email: 'mara@example.test', phone: '09170000000',
		customerId: '22222222-2222-4222-8222-222222222222'
	});
	await manual(event);
	assert.equal(event.calls[0][0], 'herco_create_staff_booking_configured');
	assert.equal(event.calls[0][1].customer_email, 'mara@example.test');
});

test('staff name groups use the requested surface and protect the lookup', async () => {
	const event = request({ surface: 'history', name: 'Mara  Villanueva', page: 2 });
	assert.equal((await groups(event)).status, 200);
	assert.deepEqual(event.calls, [[
		'herco_staff_booking_name_groups',
		{ p_surface: 'history', p_name: 'Mara  Villanueva', p_query: '', p_page: 2 }
	]]);
	await assert.rejects(() => groups(request({ surface: 'history', page: 1 })), { status: 400 });
	await assert.rejects(() => groups(request({ surface: 'customers', page: 0 })), { status: 400 });
	await assert.rejects(() => groups(request({ surface: 'customers', page: 1 }, { failure: { code: '42501' } })), { status: 403 });
	await assert.rejects(() => groups(request({ surface: 'customers', page: 1 }, { origin: 'http://outside.test' })), { status: 403 });
});
