import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');
const migrationPath = '../supabase/migrations/202611260006_inclusive_closing_slot.sql';

test('the migration makes the closing hour bookable in the one hours rule and every function with its own arithmetic', async () => {
	const sql = await read(migrationPath);
	const code = sql.replace(/--.*/g, '');
	// window_hours is the single source for every hour check: it now ends AT the closing hour, capped at 23.
	assert.match(code, /generate_series\(coalesce\(o\.open_hour, open_h\)::integer, least\(coalesce\(o\.close_hour, close_h\)::integer, 23\)\)/);
	assert.doesNotMatch(code, /close_h\)::integer - 1/);
	// set_date_hours outside-hours check now includes the closing hour
	assert.match(code, /not between p_open_hour and least\(p_close_hour, 23\)/);
	assert.doesNotMatch(code, /p_close_hour - 1/);
	// availability, staff day view and calendar report the stored closing hour, not max(hour) + 1
	assert.doesNotMatch(code, /max\(h\.hour\) ?\+ ?1/);
	assert.match(code, /coalesce\(o\.close_hour, s\.close_hour\)/);
	assert.match(code, /win_close := case when win_open is null then null else coalesce\(own_close/);
	for (const fn of ['herco_private.window_hours', 'public.herco_availability', 'public.herco_set_date_hours', 'public.herco_staff_booking_day', 'public.herco_staff_calendar'])
		assert.ok(code.includes(`create or replace function ${fn}`), fn);
	assert.doesNotMatch(code, /\bdrop\s+(function|table)\b/i);
	assert.match(sql, /OWNER-AUTHORIZED HOSTED RELEASE/);
	assert.match(sql, /notify pgrst,'reload schema';\s*commit;\s*$/);
});

test('the migration never rewrites bookings and keeps the stored hours rules', async () => {
	const code = (await read(migrationPath)).replace(/--.*/g, '');
	assert.doesNotMatch(code, /\b(update|delete from|insert into)\s+public\.herco_bookings/i);
	assert.doesNotMatch(code, /alter table|schedule_settings\s+set|update herco_private\.schedule_settings/i);
	assert.match(code, /p_open_hour not between 0 and 23 or p_close_hour not between 1 and 24/);
});

test('the database tests are in CI and the contract no longer says closeHour - 1 is the last slot', async () => {
	assert.match(await read('../.github/workflows/engineering-checks.yml'), /tests\/database\/inclusive-closing-slot\.sql/);
	const sqlTest = await read('../tests/database/inclusive-closing-slot.sql');
	assert.match(sqlTest, /rollback;\s*$/);
	assert.match(sqlTest, /\{9,10,11,12,13,14,15,16,17\}/);
	const contract = await read('../docs/api-contract.md');
	assert.doesNotMatch(contract, /last slot starts at `closeHour - 1`\)/);
	assert.doesNotMatch(contract, /Hours are integers `9` to `16`/);
	assert.match(contract, /starts AT `closeHour`/);
});
