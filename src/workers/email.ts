import { sendBrevoEmail, type BrevoConfig, type BrevoSendResult, type TransactionalEmail } from '../lib/server/brevo.ts';

type Bindings = {
	HERCO_EMAIL_MODE?: string;
	HERCO_REMINDER_LEAD_HOURS?: string;
	SUPABASE_URL?: string;
	SUPABASE_SECRET_KEY?: string;
	BREVO_API_KEY?: string;
	EMAIL_FROM?: string;
	EMAIL_REPLY_TO?: string;
	STAGING_EMAIL_ALLOWLIST?: string;
};

type Job = {
	id: string;
	lease_token: string;
	template: string;
	recipient: string;
	payload: {
		booking_id?: unknown; visit_date?: unknown; visit_hour?: unknown;
		request_id?: unknown; target_date?: unknown; target_hour?: unknown;
	};
};

type Settlement = {
	outcome: 'accepted' | 'recipient-not-allowed' | 'rate-limited' | 'rejected' | 'ambiguous' | 'invalid-template';
	provider_id?: string;
	retry_after_seconds?: number;
};

const addressPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const visitDate = new Intl.DateTimeFormat('en-PH', { dateStyle: 'long', timeZone: 'UTC' });

function brevoConfig(env: Bindings): BrevoConfig {
	const mode = env.HERCO_EMAIL_MODE?.trim() || 'disabled';
	if (mode === 'disabled') return { mode };
	if (mode !== 'allowlist' && mode !== 'live') throw new Error('Invalid email delivery mode.');

	const apiKey = env.BREVO_API_KEY?.trim();
	const from = env.EMAIL_FROM?.trim();
	const replyTo = env.EMAIL_REPLY_TO?.trim();
	const allowedRecipients = env.STAGING_EMAIL_ALLOWLIST?.split(',').map(email => email.trim()).filter(Boolean) ?? [];
	if (!apiKey || !from || !addressPattern.test(from) ||
		(replyTo && !addressPattern.test(replyTo)) ||
		(mode === 'allowlist' && (!allowedRecipients.length || !allowedRecipients.every(email => addressPattern.test(email))))
	) throw new Error('Email delivery settings are incomplete.');

	const settings = {
		apiKey,
		from: { email: from, name: 'HERCO Detailing Garage' },
		replyTo: replyTo ? { email: replyTo } : undefined
	};
	return mode === 'allowlist' ? { ...settings, mode, allowedRecipients } : { ...settings, mode };
}

function outboxClient(env: Bindings, request: typeof fetch) {
	const projectUrl = env.SUPABASE_URL?.trim();
	const secret = env.SUPABASE_SECRET_KEY?.trim();
	if (!projectUrl || !secret || !/^(?:sb_secret_|eyJ)/.test(secret)) {
		throw new Error('Email outbox settings are incomplete.');
	}
	let project: URL;
	try {
		project = new URL(projectUrl);
	} catch {
		throw new Error('Invalid email outbox URL.');
	}
	const local = ['localhost', '127.0.0.1', '[::1]'].includes(project.hostname);
	if ((project.protocol !== 'https:' && !(local && project.protocol === 'http:')) || project.username || project.password) {
		throw new Error('Invalid email outbox URL.');
	}
	const headers = new Headers({ apikey: secret, 'content-type': 'application/json', accept: 'application/json' });
	if (secret.startsWith('eyJ')) headers.set('authorization', 'Bearer ' + secret);
	type Procedure =
		| 'herco_enqueue_appointment_reminders'
		| 'herco_claim_notification_outbox'
		| 'herco_check_reminder_outbox'
		| 'herco_check_staff_change_outbox'
		| 'herco_settle_notification_outbox';
	return async (name: Procedure, args: object): Promise<unknown> => {
		const response = await request(new URL('/rest/v1/rpc/' + name, project), {
			method: 'POST',
			headers,
			body: JSON.stringify(args),
			redirect: 'error',
			signal: AbortSignal.timeout(10_000)
		});
		if (!response.ok) throw new Error('The email outbox request failed.');
		return response.json();
	};
}

function reminderLeadHours(setting: string | undefined): number {
	const raw = setting?.trim() || '0';
	const hours = Number(raw);
	if (!/^\d{1,3}$/.test(raw) || hours > 168) throw new Error('Invalid appointment reminder lead time.');
	return hours;
}

function visitLabel(date: unknown, hour: unknown, dayOnly = false): string | undefined {
	if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return;
	const day = new Date(date + 'T00:00:00Z');
	if (!Number.isFinite(day.getTime()) || day.toISOString().slice(0, 10) !== date) return;
	if (dayOnly) return visitDate.format(day) + ' Philippine time';
	if (typeof hour !== 'number' || !Number.isInteger(hour) || hour < 0 || hour > 23) return;
	return visitDate.format(day) + ' at ' + (hour % 12 || 12) + ':00 ' + (hour < 12 ? 'AM' : 'PM') + ' Philippine time';
}

function staffChangeTemplate(template: string) {
	return template === 'staff_booking_cancel_requested' || template === 'staff_booking_reschedule_requested';
}

function renderJob(job: Job): TransactionalEmail | undefined {
	const { booking_id: id, visit_date: date, visit_hour: hour, request_id: requestId, target_date: targetDate, target_hour: targetHour } = job.payload ?? {};
	const walkIn = job.template === 'walk_in_submitted' || job.template === 'walk_in_confirmed' || job.template === 'walk_in_cancelled';
	const when = visitLabel(date, hour, walkIn);
	if (typeof id !== 'string' || !/^[a-z0-9-]{1,80}$/i.test(id) || !when) return;
	const reference = 'Booking reference: ' + id;
	const to = { email: job.recipient };
	if (staffChangeTemplate(job.template)) {
		if (typeof requestId !== 'string' || !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(requestId)) return;
		const reschedule = job.template === 'staff_booking_reschedule_requested';
		const proposed = reschedule ? visitLabel(targetDate, targetHour) : undefined;
		if (reschedule && !proposed) return;
		const action = reschedule ? 'reschedule' : 'cancellation';
		return {
			to,
			subject: 'HERCO ' + action + ' request needs review',
			text: 'A customer submitted a ' + action + ' request.\n\n' + reference +
				'\nRequest reference: ' + requestId + '\nCurrent visit: ' + when +
				(proposed ? '\nRequested visit: ' + proposed : '') +
				'\n\nOpen Change requests in the HERCO staff workspace to review it.'
		};
	}
	switch (job.template) {
		case 'walk_in_submitted':
			return { to, subject: 'HERCO walk-in received',
				text: 'The shop received your signed walk-in for review on ' + when + '.\n\n' + reference + '\n\nVisit My Bookings for the latest status.' };
		case 'walk_in_confirmed':
			return { to, subject: 'HERCO walk-in confirmed',
				text: 'The shop confirmed your walk-in for ' + when + '.\n\n' + reference + '\n\nVisit My Bookings for the latest status.' };
		case 'walk_in_cancelled':
			return { to, subject: 'HERCO walk-in cancelled',
				text: 'The shop cancelled your walk-in for ' + when + '.\n\n' + reference + '\n\nVisit My Bookings for the latest status.' };
		case 'booking_submitted':
			return {
				to,
				subject: 'HERCO booking request received',
				text: 'We received your booking request for ' + when + '.\n\n' + reference + '\n\nVisit My Bookings for the latest status.'
			};
		case 'booking_confirmed':
			return {
				to,
				subject: 'HERCO booking confirmed',
				text: 'Your booking was confirmed for ' + when + '.\n\n' + reference + '\n\nVisit My Bookings for the latest visit details.'
			};
		case 'booking_cancel_approved':
			return {
				to,
				subject: 'HERCO cancellation approved',
				text: 'The shop approved the cancellation of your booking.\n\n' + reference + '\n\nVisit My Bookings for the latest status.'
			};
		case 'booking_cancelled_by_staff':
			return {
				to,
				subject: 'HERCO booking cancelled',
				text: 'The shop cancelled your booking for ' + when + '.\n\n' + reference + '\n\nVisit My Bookings for the latest status.'
			};
		case 'booking_cancel_declined':
			return {
				to,
				subject: 'HERCO cancellation request declined',
				text: 'The shop declined your cancellation request. Your scheduled visit was ' + when + '.\n\n' + reference + '\n\nVisit My Bookings for the latest status.'
			};
		case 'booking_reschedule_approved':
			return {
				to,
				subject: 'HERCO reschedule approved',
				text: 'The shop approved moving your visit to ' + when + '.\n\n' + reference + '\n\nVisit My Bookings for the latest visit details.'
			};
		case 'booking_rescheduled_by_staff':
			return {
				to,
				subject: 'HERCO booking rescheduled',
				text: 'The shop moved your booking to ' + when + '.\n\n' + reference + '\n\nVisit My Bookings for the latest visit details.'
			};
		case 'booking_reschedule_declined':
			return {
				to,
				subject: 'HERCO reschedule request declined',
				text: 'The shop declined your reschedule request. Your scheduled visit was ' + when + '.\n\n' + reference + '\n\nVisit My Bookings for the latest status.'
			};
		case 'appointment_reminder':
			return {
				to,
				subject: 'Reminder for your upcoming HERCO visit',
				text: 'Your upcoming HERCO appointment is scheduled for ' + when + '.\n\n' + reference + '\n\nVisit My Bookings for the latest visit details.'
			};
	}
}

function settlement(result: BrevoSendResult): Settlement {
	switch (result.status) {
		case 'accepted':
			return result.messageId.length <= 500
				? { outcome: 'accepted', provider_id: result.messageId }
				: { outcome: 'ambiguous' };
		case 'skipped':
			if (result.reason !== 'recipient-not-allowed') throw new Error('Delivery was disabled after claiming mail.');
			return { outcome: 'recipient-not-allowed' };
		case 'retry':
			return { outcome: 'rate-limited', retry_after_seconds: Math.min(86400, result.retryAfterSeconds ?? 0) };
		case 'rejected':
			return { outcome: 'rejected' };
		case 'unknown':
			return { outcome: 'ambiguous' };
	}
}

export async function deliverNotificationBatch(env: Bindings, request: typeof fetch = fetch) {
	const config = brevoConfig(env);
	if (config.mode === 'disabled') return;

	const rpc = outboxClient(env, request);
	const leadHours = reminderLeadHours(env.HERCO_REMINDER_LEAD_HOURS);
	if (leadHours) await rpc('herco_enqueue_appointment_reminders', { lead_hours: leadHours });
	const jobs = await rpc('herco_claim_notification_outbox', { batch_size: 5, include_reminders: leadHours > 0 });
	if (!Array.isArray(jobs) || jobs.length > 5) throw new Error('Invalid email outbox batch.');
	const results = await Promise.allSettled((jobs as Job[]).map(async job => {
		const check = job.template === 'appointment_reminder' ? 'herco_check_reminder_outbox'
			: staffChangeTemplate(job.template) ? 'herco_check_staff_change_outbox' : undefined;
		if (check) {
			const current = await rpc(check, { job_id: job.id, claim_token: job.lease_token });
			if (current === 'stale') return 'stale';
			if (current !== 'ready') throw new Error('Could not verify the notification is still current.');
		}
		const message = renderJob(job);
		const resolved = message ? settlement(await sendBrevoEmail(config, message, request)) : { outcome: 'invalid-template' };
		const saved = await rpc('herco_settle_notification_outbox', {
			job_id: job.id,
			claim_token: job.lease_token,
			...resolved
		});
		if (saved !== true) throw new Error('Could not settle the claimed notification.');
		return resolved.outcome;
	}));

	const alerts = results.filter(result => result.status === 'rejected' ||
		(result.status === 'fulfilled' && ['ambiguous', 'rejected', 'invalid-template'].includes(result.value)));
	if (alerts.length) throw new Error(alerts.length + ' email outbox job(s) require review.');
}

export default {
	async scheduled(_controller: unknown, env: Bindings) {
		await deliverNotificationBatch(env);
	}
};
