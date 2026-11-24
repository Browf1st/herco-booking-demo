// Demo version of the opening-hours screens' save calls (browser storage only). Loaded on demand from the admin page.
import { nowHour, today } from '../shared/dates';
import { hoursForDate, hoursIssue, hourText, visitsOutside, weekdayChoices, type DateAction, type DayInfo, type Needs, type OutsideBooking, type ScheduleSettings } from '../shared/schedule-hours';
import { canPerform, requireStaffAction, staffActor } from './staffAccess.svelte.ts';
import { audit, bookingsOn, dateOverride, dayHours, db, isSlotBlocked, setDateAvailability, toggleSlotBlock } from './store.svelte';

// Bookings still ahead, not cancelled, that hold an hour (walk-ins without a time hold none).
const futureVisits = (): OutsideBooking[] => db.bookings
	.filter(b => b.status !== 'cancelled' && !b.walkIn?.immediate && (b.date > today() || (b.date === today() && Number.parseInt(b.slot) > nowHour())))
	.map(b => ({ reference: b.id, date: b.date, hour: Number.parseInt(b.slot) }));

const needsOk = (visits: OutsideBooking[]): Needs | undefined => visits.length ? { bookings: visits.slice(0, 100), count: visits.length } : undefined;

// One date as the Manage availability panel shows it.
export function dayInfo(date: string): DayInfo {
	const { closed, openHour, closeHour, hours } = dayHours(date);
	const own = db.dateHours[date];
	const bookings = bookingsOn(date);
	return {
		closed, past: date < today(), override: db.blocked.includes(date) ? false : db.opened.includes(date) ? true : null,
		openHour: closed ? null : openHour, closeHour: closed ? null : closeHour, ownOpen: own?.openHour ?? null, ownClose: own?.closeHour ?? null,
		hours: hours.map(hour => {
			const blocked = isSlotBlocked(date, String(hour).padStart(2, '0') + ':00');
			const past = date < today() || (date === today() && hour <= nowHour());
			return { hour, blocked, status: past ? 'past' : blocked ? 'blocked' : 'open', booked: bookings.filter(b => Number.parseInt(b.slot) === hour).length };
		})
	};
}

export const loadSettings = async () => ({
	openHour: db.hours.openHour, closeHour: db.hours.closeHour, openWeekdays: [...db.hours.openWeekdays], canManage: canPerform('manageSchedule')
});

export async function saveSettings(values: ScheduleSettings, confirmOutside: boolean) {
	requireStaffAction('manageSchedule');
	const issue = hoursIssue(values.openHour, values.closeHour, values.openWeekdays);
	if (issue) throw Error(issue);
	const next = { ...values, openWeekdays: [...values.openWeekdays] };
	if (!confirmOutside) {
		const needs = needsOk(visitsOutside(futureVisits(), dayHours, date => hoursForDate(next, date, dateOverride(date))));
		if (needs) return needs;
	}
	db.hours = next;
	const days = weekdayChoices.filter(item => next.openWeekdays.includes(item.day)).map(item => item.label).join(' ');
	audit(`Changed default hours to ${hourText(next.openHour)} to ${hourText(next.closeHour)}, open ${days}`, undefined, staffActor(), 'Booking calendar');
}

export async function changeDate(date: string, { action, hour, openHour, closeHour }: DateAction, confirmOutside: boolean): Promise<Needs | undefined> {
	const choices = { open_date: 'open', close_date: 'closed', restore_date: 'regular' } as const;
	if (action in choices) return void setDateAvailability(date, choices[action as keyof typeof choices]);
	if (action === 'block_slot' || action === 'unblock_slot') {
		const time = String(hour).padStart(2, '0') + ':00';
		if (isSlotBlocked(date, time) !== (action === 'unblock_slot')) return;
		return void toggleSlotBlock(date, time);
	}
	if (action !== 'set_date_hours' || openHour === undefined || closeHour === undefined) throw Error('Unknown change.');
	requireStaffAction('manageSchedule');
	if (date < today()) throw Error('Choose today or a future date.');
	const issue = hoursIssue(openHour, closeHour);
	if (issue) throw Error(issue);
	if (!confirmOutside) {
		const visits = futureVisits().filter(visit => visit.date === date);
		const needs = needsOk(visitsOutside(visits, dayHours, day => hoursForDate(db.hours, day, { ownOpen: openHour, ownClose: closeHour })));
		if (needs) return needs;
	}
	db.blocked = db.blocked.filter(day => day !== date);
	if (!db.opened.includes(date)) db.opened.push(date);
	db.dateHours[date] = { openHour, closeHour };
	audit(`Set hours for ${date}: ${hourText(openHour)} to ${hourText(closeHour)}`, undefined, staffActor(), 'Booking calendar');
}
