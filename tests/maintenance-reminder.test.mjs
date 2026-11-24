import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import {
	hourLabel, maintenanceDueAt, manilaDate, openDaysLabel, parseMaintenanceCheck, parseSiteUrl, renderMaintenanceEmail
} from '../src/lib/server/maintenance-reminder.ts';
import { parseReminderSetting, parseUnsubscribeBody } from '../src/lib/server/reminder-input.ts';
import { signUnsubscribeToken, verifyUnsubscribeToken } from '../src/lib/server/reminder-token.ts';
import { deliverNotificationBatch } from '../src/workers/email.ts';

const SECRET = 'fixture-secret-fixture-secret-0123456789';
const OTHER_SECRET = 'another-secret-another-secret-9876543210';
const CUSTOMER = '00000000-0000-4000-8000-000000000501';
const OTHER_CUSTOMER = '00000000-0000-4000-8000-000000000502';
const NOW = Date.UTC(2026, 10, 23, 0, 0, 0);

// ---------------------------------------------------------------- date math

test('reminder is due at 9 AM Philippine time, 6 months after the Done date', () => {
	assert.equal(maintenanceDueAt('2026-01-10').toISOString(), '2026-07-10T01:00:00.000Z');
	assert.equal(maintenanceDueAt('2026-07-10').toISOString(), '2027-01-10T01:00:00.000Z');
	assert.equal(maintenanceDueAt('2026-11-23').toISOString(), '2027-05-23T01:00:00.000Z');
});

test('month-end dates clamp to the last day of the target month', () => {
	assert.equal(maintenanceDueAt('2026-08-31').toISOString(), '2027-02-28T01:00:00.000Z');
	assert.equal(maintenanceDueAt('2027-08-31').toISOString(), '2028-02-29T01:00:00.000Z');
	assert.equal(maintenanceDueAt('2026-12-31').toISOString(), '2027-06-30T01:00:00.000Z');
	assert.equal(maintenanceDueAt('2026-07-31').toISOString(), '2027-01-31T01:00:00.000Z');
	assert.equal(maintenanceDueAt('2026-09-30').toISOString(), '2027-03-30T01:00:00.000Z');
	assert.equal(maintenanceDueAt('2028-02-29').toISOString(), '2028-08-29T01:00:00.000Z');
});

test('9 AM in Manila is 01:00 UTC and reads back as 9:00 in Asia/Manila', () => {
	const due = maintenanceDueAt('2026-03-15');
	const manila = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Manila', hour: '2-digit', minute: '2-digit', hour12: false }).format(due);
	assert.equal(manila, '09:00');
	assert.equal(manilaDate(due), '2026-09-15');
});

test('the Done date is the Philippine date, not the UTC date', () => {
	assert.equal(manilaDate(new Date('2026-01-10T15:59:00Z')), '2026-01-10');
	assert.equal(manilaDate(new Date('2026-01-10T16:00:00Z')), '2026-01-11');
});

test('impossible or malformed done dates are refused', () => {
	for (const bad of ['2026-02-30', '2026-13-01', '2026-1-1', '', 'tomorrow', '2026-01-10T00:00:00Z']) {
		assert.throws(() => maintenanceDueAt(bad), /Invalid done date/, bad);
	}
});

// ---------------------------------------------------------------- unsubscribe token

test('a signed token verifies and carries only the customer id', async () => {
	const token = await signUnsubscribeToken(CUSTOMER, SECRET, NOW);
	assert.match(token, /^v1\.[0-9a-f-]{36}\.\d+\.[A-Za-z0-9_-]{43}$/);
	assert.ok(!token.includes('@'));
	assert.equal(await verifyUnsubscribeToken(token, SECRET, NOW), CUSTOMER);
	assert.equal(await verifyUnsubscribeToken(token, SECRET, NOW + 364 * 86400 * 1000), CUSTOMER);
});

test('a token expires after one year', async () => {
	const token = await signUnsubscribeToken(CUSTOMER, SECRET, NOW);
	assert.equal(await verifyUnsubscribeToken(token, SECRET, NOW + 366 * 86400 * 1000), undefined);
	assert.equal(await verifyUnsubscribeToken(token, SECRET, NOW + 365 * 86400 * 1000), undefined);
});

test('a token signed with another secret, or edited, is refused', async () => {
	const token = await signUnsubscribeToken(CUSTOMER, SECRET, NOW);
	assert.equal(await verifyUnsubscribeToken(token, OTHER_SECRET, NOW), undefined);
	const [version, id, expiry, signature] = token.split('.');
	assert.equal(await verifyUnsubscribeToken([version, OTHER_CUSTOMER, expiry, signature].join('.'), SECRET, NOW), undefined);
	assert.equal(await verifyUnsubscribeToken([version, id, Number(expiry) + 86400 * 365, signature].join('.'), SECRET, NOW), undefined);
	const flipped = signature.slice(0, -1) + (signature.endsWith('A') ? 'B' : 'A');
	assert.equal(await verifyUnsubscribeToken([version, id, expiry, flipped].join('.'), SECRET, NOW), undefined);
	assert.equal(await verifyUnsubscribeToken([version, id, expiry].join('.'), SECRET, NOW), undefined);
	assert.equal(await verifyUnsubscribeToken(token + '.extra', SECRET, NOW), undefined);
	assert.equal(await verifyUnsubscribeToken('v2' + token.slice(2), SECRET, NOW), undefined);
});

test('junk input never verifies and never throws', async () => {
	for (const junk of [undefined, null, 42, {}, [], '', 'abc', '....', 'v1.not-a-uuid.1.x', 'a'.repeat(500), "'; drop table x; --"]) {
		assert.equal(await verifyUnsubscribeToken(junk, SECRET, NOW), undefined, String(junk));
	}
});

test('signing needs a long secret and a real customer id', async () => {
	await assert.rejects(signUnsubscribeToken(CUSTOMER, 'short', NOW), /too short/);
	await assert.rejects(signUnsubscribeToken('not-a-uuid', SECRET, NOW), /Invalid customer id/);
	assert.equal(await verifyUnsubscribeToken('v1.' + CUSTOMER + '.99999999999.' + 'A'.repeat(43), SECRET, NOW), undefined);
});

// ---------------------------------------------------------------- route input

test('unsubscribe body must hold a token string', () => {
	assert.deepEqual(parseUnsubscribeBody({ token: ' abc ' }), { value: { token: 'abc' } });
	for (const bad of [null, undefined, 'x', {}, { token: '' }, { token: '   ' }, { token: 5 }, { token: ['a'] }, { token: 'a'.repeat(201) }]) {
		assert.ok('message' in parseUnsubscribeBody(bad), JSON.stringify(bad));
	}
});

test('account switch accepts only a real boolean', () => {
	assert.deepEqual(parseReminderSetting({ maintenance: true }), { value: { maintenance: true } });
	assert.deepEqual(parseReminderSetting({ maintenance: false }), { value: { maintenance: false } });
	for (const bad of [null, undefined, {}, { maintenance: 'true' }, { maintenance: 1 }, { maintenance: 0 }, { maintenance: null }, []]) {
		assert.ok('message' in parseReminderSetting(bad), JSON.stringify(bad));
	}
});

test('route files verify the token before touching the database and keep the same-origin rule', async () => {
	const unsubscribe = await readFile(new URL('../src/routes/api/reminders/unsubscribe/+server.ts', import.meta.url), 'utf8');
	assert.ok(unsubscribe.indexOf('requireSameOrigin(event)') < unsubscribe.indexOf('await readJsonBody('));
	assert.ok(unsubscribe.indexOf('verifyUnsubscribeToken(') < unsubscribe.indexOf('createClient('));
	assert.match(unsubscribe, /status: 204/);
	const account = await readFile(new URL('../src/routes/api/account/reminders/+server.ts', import.meta.url), 'utf8');
	assert.match(account, /export const GET/);
	assert.match(account, /export const PUT[\s\S]*requireSameOrigin\(event\)/);
	assert.doesNotMatch(account, /customer_id|user_id|body\.id/);
});

// ---------------------------------------------------------------- email wording

const check = (overrides = {}) => ({ firstName: 'Ana', services: ['Ceramic coating'], openHour: 9, closeHour: 17, openWeekdays: [0, 3, 4, 5, 6], ...overrides });
const links = { bookUrl: 'https://herco.example/book', unsubscribeUrl: 'https://herco.example/reminders/unsubscribe?token=t' };

test('email uses the approved wording with current hours and open days', () => {
	const email = renderMaintenanceEmail('ana@example.test', check(), links);
	assert.equal(email.subject, 'Time for maintenance? It’s been 6 months');
	assert.equal(email.to.email, 'ana@example.test');
	assert.equal(email.text,
		'Hi Ana, it’s been 6 months since your Ceramic coating at HERCO. Time for maintenance? ' +
		'You can book any time from 9 AM to 5 PM, Wednesday to Sunday. Book here: https://herco.example/book' +
		'\n\nDon’t want these reminders? Unsubscribe: https://herco.example/reminders/unsubscribe?token=t');
});

test('email carries a List-Unsubscribe header with the same link', () => {
	const email = renderMaintenanceEmail('ana@example.test', check(), links);
	assert.deepEqual(email.headers, { 'List-Unsubscribe': '<' + links.unsubscribeUrl + '>' });
});

test('changed hours and days show in the email', () => {
	const text = renderMaintenanceEmail('a@example.test', check({ openHour: 8, closeHour: 20, openWeekdays: [1, 2, 3, 4, 5] }), links).text;
	assert.match(text, /from 8 AM to 8 PM, Monday to Friday\./);
});

test('several services, a missing name and no price or note data', () => {
	const text = renderMaintenanceEmail('a@example.test', check({ firstName: '  ', services: ['Wash', 'Ceramic coating', 'Powder coating'] }), links).text;
	assert.match(text, /^Hi there, it’s been 6 months since your Wash, Ceramic coating and Powder coating at HERCO\./);
	assert.doesNotMatch(text, /₱|PHP|centavo|note|staff/i);
});

test('hour and day labels', () => {
	assert.deepEqual([0, 9, 12, 13, 17, 23, 24].map(hourLabel), ['12 AM', '9 AM', '12 PM', '1 PM', '5 PM', '11 PM', '12 AM']);
	assert.equal(openDaysLabel([0, 3, 4, 5, 6]), 'Wednesday to Sunday');
	assert.equal(openDaysLabel([6, 0]), 'Saturday and Sunday');
	assert.equal(openDaysLabel([1, 3, 5]), 'Monday, Wednesday and Friday');
	assert.equal(openDaysLabel([2]), 'Tuesday');
	assert.equal(openDaysLabel([0, 1, 2, 3, 4, 5, 6]), 'every day');
	assert.equal(openDaysLabel([1, 2, 3]), 'Monday to Wednesday');
});

test('site address must be https (or localhost) with no path', () => {
	assert.equal(parseSiteUrl('https://herco.example'), 'https://herco.example');
	assert.equal(parseSiteUrl(' https://herco.example/ '), 'https://herco.example');
	assert.equal(parseSiteUrl('http://localhost:5173'), 'http://localhost:5173');
	for (const bad of [undefined, '', 'herco.example', 'http://herco.example', 'https://herco.example/app', 'https://u:p@herco.example', 'https://herco.example?x=1', 'javascript:alert(1)']) {
		assert.equal(parseSiteUrl(bad), undefined, String(bad));
	}
});

test('database re-check answers are read strictly', () => {
	assert.equal(parseMaintenanceCheck({ status: 'stale' }), 'stale');
	assert.deepEqual(parseMaintenanceCheck({ status: 'ready', ...check() }), check());
	for (const bad of [null, undefined, 'ready', {}, { status: 'ready' }, { status: 'ready', ...check({ openHour: 17, closeHour: 9 }) },
		{ status: 'ready', ...check({ services: 'x' }) }, { status: 'ready', ...check({ openWeekdays: [] }) },
		{ status: 'ready', ...check({ openWeekdays: [7] }) }, { status: 'ready', ...check({ firstName: 5 }) }]) {
		assert.throws(() => parseMaintenanceCheck(bad), /still current/, JSON.stringify(bad));
	}
});

// ---------------------------------------------------------------- worker skip rules

function fakeServices(job, checkAnswer) {
	const calls = [];
	const request = async (url, init) => {
		const target = String(url);
		const body = init?.body ? JSON.parse(init.body) : {};
		if (target.startsWith('https://api.brevo.com/')) {
			calls.push({ name: 'brevo', body });
			return new Response(JSON.stringify({ messageId: '<fixture@example.test>' }), { status: 201 });
		}
		const name = new URL(target).pathname.split('/').pop();
		calls.push({ name, body });
		const answers = {
			herco_claim_notification_outbox: job ? [job] : [],
			herco_check_maintenance_reminder_outbox: checkAnswer,
			herco_settle_notification_outbox: true
		};
		return new Response(JSON.stringify(answers[name]), { status: 200 });
	};
	return { calls, request };
}

const baseEnv = {
	HERCO_EMAIL_MODE: 'live', SUPABASE_URL: 'https://fixture.supabase.example', SUPABASE_SECRET_KEY: 'sb_secret_fixture',
	BREVO_API_KEY: 'fixture-brevo-key', EMAIL_FROM: 'shop@example.test', HERCO_REMINDER_LEAD_HOURS: '0',
	HERCO_REMINDER_TOKEN_SECRET: SECRET, HERCO_SITE_URL: 'https://herco.example'
};
const maintenanceJob = { id: '7', lease_token: '00000000-0000-4000-8000-0000000000aa', template: 'maintenance_reminder',
	recipient: 'ana@example.test', payload: { booking_id: '00000000-0000-4000-8000-0000000000bb', customer_id: CUSTOMER } };
const names = calls => calls.map(call => call.name);

test('worker sends a still-valid reminder with hours, book link and a working unsubscribe link', async () => {
	const { calls, request } = fakeServices(maintenanceJob, { status: 'ready', ...check() });
	await deliverNotificationBatch(baseEnv, request);
	assert.deepEqual(names(calls), ['herco_claim_notification_outbox', 'herco_check_maintenance_reminder_outbox', 'brevo', 'herco_settle_notification_outbox']);
	assert.equal(calls[0].body.include_maintenance, true);
	const mail = calls[2].body;
	assert.equal(mail.to[0].email, 'ana@example.test');
	assert.match(mail.textContent, /from 9 AM to 5 PM, Wednesday to Sunday\. Book here: https:\/\/herco\.example\/book/);
	const token = new URL(mail.textContent.match(/https:\/\/herco\.example\/reminders\/unsubscribe\?token=\S+/)[0]).searchParams.get('token');
	assert.equal(await verifyUnsubscribeToken(token, SECRET), CUSTOMER);
	// List-Unsubscribe header holds the same https link; no one-click POST header (the endpoint is same-origin only)
	assert.equal(mail.headers['List-Unsubscribe'], '<' + mail.textContent.match(/https:\/\/herco\.example\/reminders\/unsubscribe\?token=\S+/)[0] + '>');
	assert.equal(mail.headers['List-Unsubscribe-Post'], undefined);
	assert.equal(calls[3].body.outcome, 'accepted');
});

test('worker sends nothing and settles nothing when the database says the reminder is stale', async () => {
	const { calls, request } = fakeServices(maintenanceJob, { status: 'stale' });
	await deliverNotificationBatch(baseEnv, request);
	assert.deepEqual(names(calls), ['herco_claim_notification_outbox', 'herco_check_maintenance_reminder_outbox']);
});

test('worker does not claim maintenance reminders without the token secret or site address', async () => {
	for (const missing of ['HERCO_REMINDER_TOKEN_SECRET', 'HERCO_SITE_URL']) {
		const { calls, request } = fakeServices(null, null);
		await deliverNotificationBatch({ ...baseEnv, [missing]: '' }, request);
		assert.equal(calls[0].body.include_maintenance, false, missing);
	}
	const { calls, request } = fakeServices(null, null);
	await deliverNotificationBatch({ ...baseEnv, HERCO_REMINDER_TOKEN_SECRET: 'too-short' }, request);
	assert.equal(calls[0].body.include_maintenance, false);
});

test('worker refuses to send when the re-check answer is unreadable', async () => {
	const { calls, request } = fakeServices(maintenanceJob, { status: 'maybe' });
	await assert.rejects(deliverNotificationBatch(baseEnv, request), /require review/);
	assert.ok(!names(calls).includes('brevo'));
});

test('worker leaves other templates on the old path', async () => {
	const job = { id: '8', lease_token: maintenanceJob.lease_token, template: 'booking_submitted', recipient: 'ana@example.test',
		payload: { booking_id: 'HG-1', visit_date: '2027-01-20', visit_hour: 10 } };
	const { calls, request } = fakeServices(job, null);
	await deliverNotificationBatch(baseEnv, request);
	assert.deepEqual(names(calls), ['herco_claim_notification_outbox', 'brevo', 'herco_settle_notification_outbox']);
});

test('disabled mode does nothing', async () => {
	const { calls, request } = fakeServices(maintenanceJob, { status: 'ready', ...check() });
	await deliverNotificationBatch({ ...baseEnv, HERCO_EMAIL_MODE: 'disabled' }, request);
	assert.equal(calls.length, 0);
});
