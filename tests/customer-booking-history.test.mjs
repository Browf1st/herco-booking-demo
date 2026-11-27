import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');
const route = () => read('../src/routes/api/bookings/history/+server.ts');
const migration = () => read('../supabase/migrations/202611260005_customer_booking_history.sql');

test('route: signed-in check, uuid validation, private no-store, mapped errors', async () => {
	const src = await route();
	assert.match(src, /uuid\.test\(booking\)\) error\(400/);
	assert.match(src, /auth\.getUser\(\)/);
	assert.match(src, /if \(!user\) error\(401/);
	assert.match(src, /rpc\('herco_customer_booking_history', \{ booking \}\)/);
	assert.match(src, /42501'\) error\(403/);
	assert.match(src, /P0002'\) error\(404/);
	assert.match(src, /error\(503/);
	assert.match(src, /cache-control': 'private, no-store'/);
	assert.match(src, /json\(\{ booking_id: data\.booking_id, entries: data\.entries \}/);
	assert.doesNotMatch(src, /rpc\('herco_booking_history'/);
});

test('migration: owner-only, customer-safe columns only, no names, reasons or contact, grants', async () => {
	const sql = await migration();
	assert.match(sql, /x\.customer_id = auth\.uid\(\)/);
	assert.match(sql, /errcode = '42501'/);
	assert.match(sql, /'actor', case when r\.actor_id = b\.customer_id then 'you' else 'shop' end/);
	const code = sql.replace(/--.*/g, '');
	assert.doesNotMatch(code, /e\.reason|c\.reason|'reason'|display_name|staff_memberships|customer_profiles|customer_contact|email|phone|\bnote\b/i);
	assert.match(code, /limit 200/);
	assert.match(sql, /revoke all on function public\.herco_customer_booking_history\(uuid\) from public, anon, authenticated;/);
	assert.match(sql, /grant execute on function public\.herco_customer_booking_history\(uuid\) to authenticated;/);
	assert.doesNotMatch(sql, /grant execute[^;]*\banon\b/i);
	assert.doesNotMatch(code, /\b(insert into|update|delete from)\s+(public|herco_private)\./i);
	assert.match(sql, /OWNER-AUTHORIZED HOSTED RELEASE/);
	assert.match(sql, /notify pgrst, 'reload schema';\s*commit;\s*$/);
});

test('the database test and the contract are in place', async () => {
	assert.match(await read('../.github/workflows/engineering-checks.yml'), /tests\/database\/customer-booking-history\.sql/);
	const contract = await read('../docs/api-contract.md');
	assert.match(contract, /### `GET \/api\/bookings\/history`/);
	assert.match(await read('../tests/database/customer-booking-history.sql'), /rollback;\s*$/);
});
