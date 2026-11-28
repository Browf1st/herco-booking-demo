import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { linePriceFailure, parseLinePriceRequest, serviceConflict } from '../src/lib/server/line-price-input.ts';
import { parseRecordsRequest } from '../src/lib/server/records-input.ts';

const ok = {
	booking: '00000000-0000-4000-8000-0000000006a1', requestId: '00000000-0000-4000-8000-0000000006c1',
	service: 'ceramic', expectedCentavos: 179900, pesos: 2300, reason: 'Extra corrosion found'
};
const read = path => readFile(new URL(path, import.meta.url), 'utf8');

test('line price request: a valid body becomes centavos with a trimmed reason', () => {
	assert.deepEqual(parseLinePriceRequest({ ...ok, reason: '  Extra corrosion found  ' }), {
		booking: ok.booking, requestId: ok.requestId, service: 'ceramic', expectedCentavos: 179900, centavos: 230000, reason: 'Extra corrosion found'
	});
});

test('line price request: limits 0 and 1,000,000 pesos, a line without a price, and a 200 character reason are accepted', () => {
	assert.equal(parseLinePriceRequest({ ...ok, pesos: 0 })?.centavos, 0);
	assert.equal(parseLinePriceRequest({ ...ok, pesos: 1_000_000 })?.centavos, 100_000_000);
	assert.equal(parseLinePriceRequest({ ...ok, expectedCentavos: null })?.expectedCentavos, null);
	assert.ok(parseLinePriceRequest({ ...ok, reason: 'x'.repeat(200) }));
	assert.ok(parseLinePriceRequest({ ...ok, service: 'x'.repeat(100) }));
});

test('line price request: negative, fractional, too large, blank or odd values are refused', () => {
	for (const pesos of [-1, 1_000_001, 10.5, NaN, Infinity, '2300', null, undefined, [1], { v: 1 }, 1e21]) {
		assert.equal(parseLinePriceRequest({ ...ok, pesos }), null, String(pesos));
	}
	for (const reason of ['', '   ', 'x'.repeat(201), null, undefined, 5, ['a'], { a: 1 }]) {
		assert.equal(parseLinePriceRequest({ ...ok, reason }), null, JSON.stringify(reason));
	}
	for (const expectedCentavos of [undefined, -1, 1.5, '100', NaN, Number.MAX_SAFE_INTEGER + 1]) {
		assert.equal(parseLinePriceRequest({ ...ok, expectedCentavos }), null, String(expectedCentavos));
	}
	for (const bad of [null, 'text', [], {}, { ...ok, booking: 'x' }, { ...ok, booking: undefined }, { ...ok, requestId: '123' },
		{ ...ok, service: '' }, { ...ok, service: 'x'.repeat(101) }, { ...ok, service: 5 }, { ...ok, service: ['a'] }]) {
		assert.equal(parseLinePriceRequest(bad), null, JSON.stringify(bad));
	}
});

test('line price request: injection text is only data and still length limited', () => {
	const parsed = parseLinePriceRequest({ ...ok, reason: "x'); drop table herco_bookings;--" });
	assert.equal(parsed?.reason, "x'); drop table herco_bookings;--");
	assert.equal(parseLinePriceRequest({ ...ok, service: 'a'.repeat(101) + "'; --" }), null);
});

test('line price request: per-part prices become centavos and set the line total to their sum', () => {
	const parts = [{ label: 'Powder Coating', pesos: 2999 }, { label: 'Matte to Glossy', pesos: 8999 }];
	const parsed = parseLinePriceRequest({ ...ok, parts });
	assert.deepEqual(parsed?.parts, [{ label: 'Powder Coating', price_centavos: 299900 }, { label: 'Matte to Glossy', price_centavos: 899900 }]);
	assert.equal(parsed?.centavos, 299900 + 899900);
	// A single-part line is allowed; pesos is ignored when parts is present.
	assert.equal(parseLinePriceRequest({ ...ok, parts: [{ label: 'Base', pesos: 0 }] })?.centavos, 0);
});

test('line price request: bad parts are refused', () => {
	for (const parts of [[], Array.from({ length: 21 }, () => ({ label: 'x', pesos: 1 })), 'parts', {},
		[{ label: '', pesos: 1 }], [{ label: 'x', pesos: -1 }], [{ label: 'x', pesos: 1.5 }],
		[{ label: 'x', pesos: 1_000_001 }], [{ label: 'x', pesos: '1' }], [{ pesos: 1 }], [{ label: 'x' }]]) {
		assert.equal(parseLinePriceRequest({ ...ok, parts }), null, JSON.stringify(parts));
	}
});

test('line price failures: each database error becomes the documented answer', () => {
	assert.equal(linePriceFailure('42501').status, 403);
	assert.equal(linePriceFailure('P0002').status, 404);
	assert.equal(linePriceFailure('22023').status, 400);
	assert.deepEqual(linePriceFailure('P0423'), { status: 409, code: 'booking_locked', message: 'This booking can no longer be changed.' });
	assert.equal(linePriceFailure('P0412').status, 409);
	assert.equal(linePriceFailure('P0412').code, 'line_changed');
	for (const unknown of ['XX000', '', '57P01', '42P01']) {
		const answer = linePriceFailure(unknown);
		assert.equal(answer.status, 503);
		assert.equal(answer.code, undefined);
		assert.doesNotMatch(answer.message, /relation|sql|postgres/i);
	}
});

test('service edits: a closed booking is booking_locked, a stale revision is line_changed', () => {
	assert.equal(serviceConflict(false).code, 'booking_locked');
	assert.equal(serviceConflict(false).message, 'This booking can no longer be changed.');
	for (const canEdit of [true, undefined, null]) assert.equal(serviceConflict(canEdit).code, 'line_changed');
});

test('records request: the two new sorts pass, near misses do not', () => {
	const body = { from: '', through: '', search: '', status: 'all', source: 'all', page: 1, report: true };
	assert.equal(parseRecordsRequest({ ...body, sort: 'date_asc' })?.sort, 'date_asc');
	assert.equal(parseRecordsRequest({ ...body, sort: 'price_asc' })?.sort, 'price_asc');
	for (const sort of ['Date_asc', 'price_desc', 'date_desc', 'price asc', 'date_asc;']) assert.equal(parseRecordsRequest({ ...body, sort }), null, sort);
});

test('line price route: same-origin, signed in, parsed, and the 409 codes are returned as JSON', async () => {
	const source = await read('../src/routes/api/staff/line-price/+server.ts');
	assert.match(source, /requireSameOrigin\(event\)/);
	assert.match(source, /parseLinePriceRequest\(body\)/);
	assert.match(source, /error\(401,/);
	assert.match(source, /rpc\('herco_staff_set_line_price'/);
	assert.match(source, /json\(\{ code: answer\.code, message: answer\.message \}, \{ status: answer\.status \}\)/);
	assert.doesNotMatch(source, /service_role|SERVICE_ROLE/);
});

test('history route: signed in, validates the id, never cached, no raw database errors', async () => {
	const source = await read('../src/routes/api/staff/booking-history/+server.ts');
	assert.match(source, /uuid\.test\(booking\)/);
	assert.match(source, /error\(401,/);
	assert.match(source, /rpc\('herco_booking_history'/);
	assert.match(source, /no-store/);
	assert.doesNotMatch(source, /failure\.message/);
});

test('booking services route tells locked from stale and the contract documents both new routes', async () => {
	const route = await read('../src/routes/api/booking-services/+server.ts');
	assert.match(route, /failure\?\.code === '40001'/);
	assert.match(route, /serviceConflict\(current\?\.canEdit\)/);
	const contract = await read('../docs/api-contract.md');
	for (const text of ['POST /api/staff/line-price', 'GET /api/staff/booking-history', 'booking_locked', 'line_changed', 'date_asc', 'price_asc'])
		assert.ok(contract.includes(text), text);
});

test('My Bookings already returns current and original services and totals', async () => {
	const route = await read('../src/routes/api/bookings/+server.ts');
	for (const column of ['original_services', 'original_total_centavos', 'current_services', 'current_total_centavos'])
		assert.ok(route.includes(column), column);
});

test('the migration keeps the original snapshot, checks the grant in the database and hides money without viewIncome', async () => {
	const sql = await read('../supabase/migrations/202611240001_staff_price_edits.sql');
	assert.match(sql, /perform herco_private\.require_price_adjustment\(\)/);
	assert.match(sql, /errcode = 'P0423'/);
	assert.match(sql, /errcode = 'P0412'/);
	assert.match(sql, /new_price_centavos % 100 <> 0/);
	assert.match(sql, /update public\.herco_bookings set current_services = revised, current_total_centavos = new_total/);
	assert.doesNotMatch(sql, /set original_services|original_total_centavos\s*=/i);
	assert.match(sql, /show_money := 'viewIncome' = any\(member\.action_grants\)/);
	assert.match(sql, /applied_sort:=case when sort_by in \('price','price_asc'\) and not show_income then 'date'/);
	assert.match(sql, /revoke all on function public\.herco_staff_set_line_price/);
	assert.doesNotMatch(sql, /grant execute[^;]*\banon\b/i);
});

test('the database test is part of CI', async () => {
	const workflow = await read('../.github/workflows/engineering-checks.yml');
	assert.match(workflow, /tests\/database\/staff-price-edits\.sql/);
});
