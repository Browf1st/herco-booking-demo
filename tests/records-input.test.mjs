import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { parseRecordsRequest } from '../src/lib/server/records-input.ts';

const ok = { from: '2026-11-01', through: '2026-11-30', search: '', status: 'all', source: 'all', page: 1, report: true };

test('records request: sort defaults to date so older screens keep working', () => {
	assert.equal(parseRecordsRequest(ok)?.sort, 'date');
	assert.equal(parseRecordsRequest({ ...ok, sort: undefined })?.sort, 'date');
});

test('records request: price, status and date sorts are accepted', () => {
	for (const sort of ['date', 'price', 'status']) assert.equal(parseRecordsRequest({ ...ok, sort })?.sort, sort);
});

test('records request: unknown or odd sort values are refused', () => {
	for (const sort of ['', 'Price', 'name', 'price desc', 'price; drop table x', null, 1, true, ['price'], { by: 'price' }]) {
		assert.equal(parseRecordsRequest({ ...ok, sort }), null, JSON.stringify(sort));
	}
});

test('records request: existing filter rules are unchanged', () => {
	assert.deepEqual(parseRecordsRequest({ ...ok, from: '', through: '' }), { ...ok, from: null, through: null, sort: 'date' });
	for (const bad of [null, 'text', [], {}, { ...ok, from: '' }, { ...ok, through: '' }, { ...ok, from: '2026-1-1' }, { ...ok, search: 'x'.repeat(255) },
		{ ...ok, status: 'open' }, { ...ok, source: 'phone' }, { ...ok, page: 0 }, { ...ok, page: 501 }, { ...ok, page: 1.5 }, { ...ok, page: '1' }, { ...ok, report: 'yes' }]) {
		assert.equal(parseRecordsRequest(bad), null, JSON.stringify(bad));
	}
	assert.equal(parseRecordsRequest({ ...ok, search: 'x'.repeat(254), page: 500 })?.page, 500);
});

test('records route is same-origin, validates with the parser and passes sort to the database', async () => {
	const source = await readFile(new URL('../src/routes/api/staff/records/+server.ts', import.meta.url), 'utf8');
	assert.match(source, /requireSameOrigin\(event\)/);
	assert.match(source, /parseRecordsRequest\(body\)/);
	assert.match(source, /sort_by: query\.sort/);
});

test('the sort migration keeps money hidden without viewIncome and orders with an id tie-break', async () => {
	const sql = await readFile(new URL('../supabase/migrations/202611230003_records_sort.sql', import.meta.url), 'utf8');
	assert.match(sql, /applied_sort:=case when sort_by='price' and not show_income then 'date'/);
	assert.match(sql, /b\.visit_date desc,b\.created_at desc,b\.id desc\) as pos/);
	assert.match(sql, /strip_service_money/);
});
