// F-017 maintenance reminder: date rule, send-time check result and approved email wording.
// The database computes the real send time (trigger in 202611230002_maintenance_reminder.sql);
// maintenanceDueAt mirrors that rule so both can be tested and kept the same.

import type { TransactionalEmail } from './brevo.ts';

const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/** 9:00 AM Philippine time (UTC+8, no daylight saving) on the date 6 months after a Done date, month-end clamped. */
export function maintenanceDueAt(doneDate: string): Date {
	const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(doneDate);
	if (!match) throw new Error('Invalid done date.');
	const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
	if (new Date(Date.UTC(year, month - 1, day)).toISOString().slice(0, 10) !== doneDate) throw new Error('Invalid done date.');
	const target = month - 1 + 6;
	const targetYear = year + Math.floor(target / 12);
	const targetMonth = target % 12;
	const lastDay = new Date(Date.UTC(targetYear, targetMonth + 1, 0)).getUTCDate();
	return new Date(Date.UTC(targetYear, targetMonth, Math.min(day, lastDay), 9 - 8, 0, 0));
}

/** The Philippine calendar date (YYYY-MM-DD) of a moment. */
export function manilaDate(moment: Date): string {
	return new Date(moment.getTime() + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

export type MaintenanceCheck = {
	firstName: string;
	services: string[];
	openHour: number;
	closeHour: number;
	openWeekdays: number[];
};

const wholeHour = (value: unknown, min: number, max: number): value is number =>
	typeof value === 'number' && Number.isInteger(value) && value >= min && value <= max;

/** Reads the database re-check answer. 'stale' means the job was skipped. Anything unexpected throws. */
export function parseMaintenanceCheck(value: unknown): MaintenanceCheck | 'stale' {
	const check = value as Record<string, unknown> | null;
	if (check?.status === 'stale') return 'stale';
	const { firstName, services, openHour, closeHour, openWeekdays } = check ?? {};
	if (check?.status !== 'ready' || typeof firstName !== 'string' ||
		!Array.isArray(services) || !services.every(name => typeof name === 'string') ||
		!wholeHour(openHour, 0, 23) || !wholeHour(closeHour, 1, 24) || closeHour <= openHour ||
		!Array.isArray(openWeekdays) || !openWeekdays.length || !openWeekdays.every(day => wholeHour(day, 0, 6)) ||
		new Set(openWeekdays).size !== openWeekdays.length) {
		throw new Error('Could not verify the maintenance reminder is still current.');
	}
	return { firstName, services, openHour, closeHour, openWeekdays };
}

/** 9 -> "9 AM", 12 -> "12 PM", 17 -> "5 PM", 24 -> "12 AM". */
export function hourLabel(hour: number): string {
	return (hour % 12 || 12) + ' ' + (hour % 24 < 12 ? 'AM' : 'PM');
}

function joinNames(names: string[]): string {
	if (names.length <= 1) return names.join('');
	return names.slice(0, -1).join(', ') + ' and ' + names[names.length - 1];
}

/** [0,3,4,5,6] -> "Wednesday to Sunday". Weeks start on Monday. */
export function openDaysLabel(weekdays: number[]): string {
	const order = [...new Set(weekdays)].map(day => (day === 0 ? 7 : day)).sort((a, b) => a - b);
	if (order.length === 7) return 'every day';
	const label = (day: number) => dayNames[day % 7];
	const unbroken = order.length > 2 && order[order.length - 1] - order[0] === order.length - 1;
	if (unbroken) return label(order[0]) + ' to ' + label(order[order.length - 1]);
	return joinNames(order.map(label));
}

export function renderMaintenanceEmail(
	to: string, check: MaintenanceCheck, links: { bookUrl: string; unsubscribeUrl: string }
): TransactionalEmail {
	const first = check.firstName.trim() || 'there';
	const services = joinNames(check.services.map(name => name.trim()).filter(Boolean)) || 'visit';
	return {
		to: { email: to },
		subject: 'Time for maintenance? It’s been 6 months',
		text: 'Hi ' + first + ', it’s been 6 months since your ' + services + ' at HERCO. Time for maintenance? ' +
			'You can book any time from ' + hourLabel(check.openHour) + ' to ' + hourLabel(check.closeHour) + ', ' +
			openDaysLabel(check.openWeekdays) + '. Book here: ' + links.bookUrl +
			'\n\nDon’t want these reminders? Unsubscribe: ' + links.unsubscribeUrl,
		// Link only: the unsubscribe endpoint needs a same-origin JSON POST, so it cannot take a mail provider's
		// one-click POST (List-Unsubscribe-Post is therefore not sent).
		headers: { 'List-Unsubscribe': '<' + links.unsubscribeUrl + '>' }
	};
}

/** Public site address for links in emails: https only (http allowed for localhost). No path, no credentials. */
export function parseSiteUrl(value: string | undefined): string | undefined {
	try {
		const url = new URL(value?.trim() ?? '');
		const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
		if ((url.protocol !== 'https:' && !(local && url.protocol === 'http:')) || url.username || url.password ||
			url.pathname !== '/' || url.search || url.hash) return;
		return url.origin;
	} catch {
		return;
	}
}
