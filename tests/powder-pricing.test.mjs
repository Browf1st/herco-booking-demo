import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, readdir } from 'node:fs/promises';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');
const migrationPath = '../supabase/migrations/202611260001_powder_pricing_model.sql';
const retirePath = '../supabase/migrations/202611260002_retire_coating_price_rules.sql';

test('the migration seeds powderModel once, with the confirmed prices and the seven Basic colours', async () => {
	const sql = await read(migrationPath);
	assert.match(sql, /where singleton and not \(config \? 'powderModel'\)/);
	assert.match(sql, /"basic":\{"10-14":2199,"17":3199,"big-bike":4499,"not-sure":null\}/);
	assert.match(sql, /"special":\{"10-14":2499,"17":3499,"big-bike":5499,"not-sure":null\}/);
	assert.match(sql, /"luminous-prismatic":\{"10-14":2999,"17":3999,"big-bike":6999,"not-sure":null\}/);
	assert.match(sql, /"custom":\{"10-14":null,"17":null,"big-bike":null,"not-sure":null\}/);
	for (const name of ['Black', 'White', 'Glossy Black', 'Snow White', 'Matte Black', 'Crystal Black', 'Pristine White'])
		assert.match(sql, new RegExp(`'${name}','basic'`), name);
	assert.match(sql, /gen_random_uuid\(\)/);
	assert.match(sql, /notify pgrst,'reload schema';\s*commit;\s*$/);
	assert.match(sql, /\nbegin;\n/);
});

test('custom and not-sure are quote-only, photo paths are restricted, duplicates are rejected', async () => {
	const sql = await read(migrationPath);
	assert.match(sql, /cat='custom' or sz='not-sure'/);
	assert.match(sql, /sig=any\(sigs\)/);
	assert.match(sql, /has_price=is_quote/);
	assert.match(sql, /errcode='42501'/);
	assert.match(sql, /errcode='22023'/);
	assert.match(sql, /Check the coating rates\./);
});

test('the save keeps its lock, replay, revision check and audit; the resolver keeps the legacy branch', async () => {
	const sql = await read(migrationPath);
	assert.match(sql, /pg_advisory_xact_lock\(72017/);
	assert.match(sql, /insert into herco_private\.ui_pricing_audit/);
	assert.match(sql, /Prices changed\. Reload before editing\./);
	assert.match(sql, /coating_price_lines_legacy\(base_lines,bike,options\)/);
	assert.match(sql, /herco_private\.ui_component_price\(/);
	assert.doesNotMatch(sql, /drop\s+(table|function)/i);
	assert.doesNotMatch(sql, /(from|update|into)\s+herco_private\.coating_price_rules/i);
});

test('the migration never rewrites booking snapshots', async () => {
	const sql = await read(migrationPath);
	assert.doesNotMatch(sql, /original_services|original_total_centavos|current_services|herco_bookings/);
	assert.doesNotMatch(sql, /\b(delete from|truncate)\b/i);
});

test('the swatch target needs the pricing grant, and no new function is open to anon', async () => {
	const sql = await read(migrationPath);
	assert.match(sql, /create function public\.herco_pricing_swatch_target\(entry uuid\)/);
	assert.match(sql, /'changePricing'=any\(grants\)/);
	assert.match(sql, /revoke all on function public\.herco_pricing_swatch_target\(uuid\) from public,anon,authenticated;/);
	assert.match(sql, /grant execute on function public\.herco_pricing_swatch_target\(uuid\) to authenticated;/);
	assert.match(sql, /revoke all on function herco_private\.valid_powder_model\(jsonb\) from public,anon,authenticated;/);
	assert.match(sql, /revoke all on function herco_private\.powder_wheel_rate\(jsonb,text,jsonb\) from public,anon,authenticated;/);
	assert.doesNotMatch(sql, /grant execute[^;]*\banon\b/i);
	assert.match(sql, /herco-swatches/);
	assert.doesNotMatch(sql, /insert into storage\.buckets/i);
});

test('the database test is part of CI', async () => {
	const workflow = await read('../.github/workflows/engineering-checks.yml');
	assert.match(workflow, /tests\/database\/powder-pricing\.sql/);
	const sqlTest = await read('../tests/database/powder-pricing.sql');
	assert.match(sqlTest, /rollback;\s*$/);
});

test('colour entries can be disabled: validated, hidden from customers, never affects pricing', async () => {
	const sql = await read(migrationPath);
	assert.match(sql, /'pricesBySize','enabled'\]/);
	assert.match(sql, /jsonb_typeof\(entry->'enabled'\)<>'boolean'/);
	assert.match(sql, /'quoteOnly',false,'enabled',true\)/);
	assert.match(sql, /coalesce\(c\.value->'enabled','true'::jsonb\)<>'false'::jsonb/);
	assert.doesNotMatch(sql, /into entry from jsonb_array_elements[^;]*enabled/);
	const sqlTest = await read('../tests/database/powder-pricing.sql');
	assert.match(sqlTest, /Retired Shade/);
	assert.match(sqlTest, /disabled Custom colour still quotes/);
	assert.match(sqlTest, /Visible Shade/);
});

test('0002 migrates enabled rules, archives all rules, drops the table and never writes bookings', async () => {
	const sql = await read(retirePath);
	assert.match(sql, /drop table if exists herco_private\.coating_price_rules;/);
	assert.match(sql, /drop function if exists public\.herco_coating_rules\(\);/);
	assert.match(sql, /drop function if exists public\.herco_save_coating_rule\(/);
	assert.match(sql, /coating_price_rules_archive/);
	assert.match(sql, /'migrated:'\|\|/);
	assert.match(sql, /r\.enabled and r\.service_code='wheel-colour'/);
	assert.match(sql, /notify pgrst,'reload schema';\s*commit;\s*$/);
	assert.doesNotMatch(sql.replace(/--[^\n]*/g, ''), /original_services|original_total_centavos|current_services|herco_bookings/);
	const legacy = sql.slice(sql.indexOf('coating_price_lines_legacy(base_lines'), sql.indexOf('-- 4.'));
	assert.doesNotMatch(legacy, /coating_price_rules/);
});

test('no migration after 0002 reads the dropped table', async () => {
	const files = (await readdir(new URL('../supabase/migrations/', import.meta.url))).filter(f => f.slice(0, 12) > '202611260002');
	for (const f of files) assert.doesNotMatch(await read(`../supabase/migrations/${f}`), /herco_private\.coating_price_rules\b(?!_archive)/, f);
});

test('the retire database test is part of CI', async () => {
	const workflow = await read('../.github/workflows/engineering-checks.yml');
	assert.match(workflow, /tests\/database\/powder-pricing-retire\.sql/);
	const sqlTest = await read('../tests/database/powder-pricing-retire.sql');
	assert.match(sqlTest, /to_regclass\('herco_private\.coating_price_rules'\) is not null/);
	assert.match(sqlTest, /rollback;\s*$/);
});

test('QA fixes: unknown finish quotes, 40,000 byte cap, photo path must use the entry id, data move is tested', async () => {
	const sql = await read(migrationPath);
	assert.match(sql, /cat:=entry->>'category'/);
	assert.match(sql, /if entry is null or cat='custom'/);
	assert.doesNotMatch(sql, /coalesce\(entry->>'category','special'\)/);
	assert.match(sql, /pg_column_size\(configuration\)>40000/);
	assert.doesNotMatch(sql, /pg_column_size\(configuration\)>20000/);
	assert.ok(sql.includes("('^entry/'||(entry->>'id')||'\\.(webp|jpg|png)$')"), 'photoPath must embed the entry id');
	const sqlTest = await read('../tests/database/powder-pricing.sql');
	assert.match(sqlTest, /unknown colour quotes/);
	assert.match(sqlTest, /belongs to another entry's id is refused/);
	const retire = await read('../tests/database/powder-pricing-retire.sql');
	for (const text of ['retire_coating_price_rules_data()', 'migrated:00000000-0000-4000-8000-0000000007a1', 'not idempotent', 'Archive is missing rules'])
		assert.ok(retire.includes(text), text);
	const contract = await read('../docs/api-contract.md');
	assert.doesNotMatch(contract, /20,000 chars JSON/);
});

test('F-022 server step: new option keys, size keys, no Raider/Sniper gate, colour-id pricing, tests and contract', async () => {
	const sql = await read('../supabase/migrations/202611260003_powder_booking_options.sql');
	for (const key of ['powder_category', 'color_id', 'custom_note', 'from_finish', 'raider_sniper_confirmed'])
		assert.ok(sql.includes(`'${key}'`), key);
	assert.match(sql, /'10-14','17','big-bike','not-sure'\) then/);
	assert.match(sql, /left\(btrim\(regexp_replace\(c->>'custom_note'.*,300\)/);
	assert.match(sql, /options-'ui_catalog'-'raider_sniper_confirmed'/);
	assert.doesNotMatch(sql.replace(/--.*/g, ''), /supports_seventeen_inch_mags/);
	assert.match(sql, /Check the motorcycle year, notes and wheel configuration\./);
	assert.match(sql, /notify pgrst,'reload schema';\s*commit;\s*$/);
	assert.match(sql, /OWNER-AUTHORIZED HOSTED RELEASE/);
	assert.doesNotMatch(sql.replace(/--[^\n]*/g, ''), /original_services|original_total_centavos|current_services|herco_bookings/);
	assert.doesNotMatch(sql, /grant execute[^;]*\banon\b/i);
	const workflow = await read('../.github/workflows/engineering-checks.yml');
	assert.match(workflow, /tests\/database\/powder-booking-options\.sql/);
	const contract = await read('../docs/api-contract.md');
	for (const text of ['F-022 note', 'powder_category', 'color_id', 'custom_note', 'raider_sniper_confirmed'])
		assert.ok(contract.includes(text), text);
});

test('F-023: ceramic exceptions are validated, resolved first, and fall back to the tier price', async () => {
	const sql = await read('../supabase/migrations/202611260004_ceramic_exceptions.sql');
	assert.match(sql, /not in\('wheel-colour','ceramic'\)/);
	assert.match(sql, /'ceramic\|'\|\|\(ex->>'bikeKey'\)/);
	assert.match(sql, /create function herco_private\.ceramic_exception_rate\(config jsonb, bike text\)/);
	assert.match(sql, /x\.value->>'service'='ceramic'/);
	assert.match(sql, /case when cex is null then config->'ceramic'->'tiers'->tier else cex end/);
	assert.match(sql, /revoke all on function herco_private\.ceramic_exception_rate\(jsonb,text\) from public,anon,authenticated;/);
	assert.match(sql, /OWNER-AUTHORIZED HOSTED RELEASE/);
	assert.match(sql, /notify pgrst,'reload schema';\s*commit;\s*$/);
	assert.doesNotMatch(sql.replace(/--.*/g, ''), /original_services|original_total_centavos|current_services|herco_bookings/);
	assert.doesNotMatch(sql, /grant execute[^;]*\banon\b/i);
	const workflow = await read('../.github/workflows/engineering-checks.yml');
	assert.match(workflow, /tests\/database\/ceramic-exceptions\.sql/);
	const contract = await read('../docs/api-contract.md');
	assert.match(contract, /F-023 note/);
	assert.match(contract, /service: "ceramic"/);
});
