import assert from 'node:assert/strict';
import test from 'node:test';
import { handle } from '../src/hooks.server.ts';
import { MAX_JSON_BYTES, readJsonBody } from '../src/lib/server/request-body.ts';

const endpoint = 'https://herco.example.test/api/bookings';
const encoder = new TextEncoder();

function streamRequest(chunks, onCancel) {
	return new Request(endpoint, {
		method: 'POST',
		duplex: 'half',
		body: new ReadableStream({
			pull(controller) {
				if (chunks.length) controller.enqueue(chunks.shift());
				else controller.close();
			},
			cancel: onCancel
		})
	});
}

test('reads valid JSON at the byte limit and across UTF-8 chunks', async () => {
	const text = JSON.stringify('ñ' + 'a'.repeat(MAX_JSON_BYTES - 4));
	const encoded = encoder.encode(text);
	assert.equal(encoded.length, MAX_JSON_BYTES);
	assert.equal(await readJsonBody(streamRequest([encoded.subarray(0, 2), encoded.subarray(2)])), JSON.parse(text));
});

test('returns a 413 before reading a declared oversized JSON body', async () => {
	const request = new Request(endpoint, {
		method: 'POST',
		headers: { 'content-length': String(MAX_JSON_BYTES + 1) },
		body: '{}'
	});
	await assert.rejects(readJsonBody(request), { status: 413 });
	assert.equal(request.bodyUsed, false);
});

test('rejects an oversized stream without depending on Content-Length', async () => {
	let cancelled = false;
	const request = streamRequest([
		new Uint8Array(MAX_JSON_BYTES), new Uint8Array(1), new Uint8Array(1)
	], () => { cancelled = true; });
	assert.equal(request.headers.get('content-length'), null);
	await assert.rejects(readJsonBody(request), { status: 413 });
	assert.equal(cancelled, true);
});

test('returns null for missing, malformed and invalid UTF-8 bodies', async () => {
	assert.equal(await readJsonBody(new Request(endpoint, { method: 'POST' })), null);
	assert.equal(await readJsonBody(streamRequest([encoder.encode('{"broken":')])), null);
	assert.equal(await readJsonBody(streamRequest([new Uint8Array([34, 255, 34])])), null);
});

const routeResponse = (response, route = '/api/bookings') => handle({
	event: { route: { id: route }, url: new URL(route ?? '/not-found', endpoint) },
	resolve: async () => response
});

test('adds security and private cache headers to an API validation error', async () => {
	const response = await routeResponse(Response.json({ message: 'Check the booking.' }, { status: 400 }));
	assert.equal(response.status, 400);
	assert.equal(response.headers.get('cache-control'), 'private, no-store');
	assert.equal(response.headers.get('content-security-policy'), "frame-ancestors 'none'");
	assert.equal(response.headers.get('x-frame-options'), 'DENY');
	assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
	assert.match(response.headers.get('permissions-policy'), /camera=\(self\)/);
	assert.equal(response.headers.get('referrer-policy'), 'strict-origin-when-cross-origin');
	assert.deepEqual(await response.json(), { message: 'Check the booking.' });
});

test('preserves the existing policy and distinct cookies, and never shares cookie responses', async () => {
	const headers = new Headers({
		'cache-control': 'public, max-age=60',
		'content-security-policy': "default-src 'self'",
		'referrer-policy': 'no-referrer'
	});
	const cookies = ['one=test; Path=/; HttpOnly', 'two=test; Path=/; HttpOnly'];
	for (const cookie of cookies) headers.append('set-cookie', cookie);
	const response = await routeResponse(new Response(null, { status: 204, headers }));
	assert.equal(response.status, 204);
	assert.equal(response.headers.get('content-security-policy'), "default-src 'self', frame-ancestors 'none'");
	assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
	assert.deepEqual(response.headers.getSetCookie(), cookies);
	assert.equal(response.headers.get('cache-control'), 'private, no-store');
});

test('preserves explicit public cache on successful responses and redirects still work', async () => {
	const asset = await routeResponse(new Response('catalog', { headers: { 'cache-control': 'public, max-age=60' } }));
	assert.equal(asset.headers.get('cache-control'), 'public, max-age=60');
	const redirect = await routeResponse(Response.redirect('https://herco.example.test/account'), null);
	assert.equal(redirect.status, 302);
	assert.equal(redirect.headers.get('location'), 'https://herco.example.test/account');
});
