// Opening-hours rules shared by both builds (F-002). Hours are whole hours 0-24 in shop time.
// Weekdays follow Date.getUTCDay(): 0 is Sunday.
// `version` comes from the Worker server only (it spots two admins saving at once). The demo has none.
export type ScheduleSettings = { openHour: number; closeHour: number; openWeekdays: number[]; version?: string };export type DateOverride = { closed?: boolean; open?: boolean; ownOpen?: number; ownClose?: number };
export type DayHours = { closed: boolean; openHour: number; closeHour: number; hours: number[] };
export type OutsideBooking = { reference: string; date: string; hour: number };
// One date as the Manage Availability panel shows it (the staff day view in both builds).
export type DayHourRow = { hour: number; status: 'open' | 'past' | 'blocked'; blocked: boolean; booked: number };
export type DayInfo = {
	closed: boolean; past: boolean; override: boolean | null; openHour: number | null; closeHour: number | null;
	ownOpen: number | null; ownClose: number | null; hours: DayHourRow[];
};
export type DateAction = { action: string; hour?: number; openHour?: number; closeHour?: number };
// What a save returns when it needs the admin's OK first (the 409 bookings_outside_hours answer).
export type Needs = { bookings: OutsideBooking[]; count: number };

export const defaultSettings = (): ScheduleSettings => ({ openHour: 9, closeHour: 17, openWeekdays: [0, 3, 4, 5, 6] });

// Monday first, like the calendars.
export const weekdayChoices = [
	{ day: 1, label: 'Mon' }, { day: 2, label: 'Tue' }, { day: 3, label: 'Wed' }, { day: 4, label: 'Thu' },
	{ day: 5, label: 'Fri' }, { day: 6, label: 'Sat' }, { day: 0, label: 'Sun' }
];

export const hourText = (hour: number) => `${hour % 12 || 12} ${hour % 24 < 12 ? 'AM' : 'PM'}`;
export const closeText = (hour: number) => hour === 24 ? '12 AM (midnight)' : hourText(hour);
export const hourRange = (openHour: number, closeHour: number) =>
	Array.from({ length: Math.max(0, closeHour - openHour) }, (_, i) => openHour + i);
export const openOptions = hourRange(0, 24);
export const closeOptions = hourRange(1, 25);
// Bookable slots now INCLUDE the closing hour (F-026: 5 PM bookable for a 9–17 shop).
// Keep hourRange (exclusive) for the open/close dropdowns above; use slotHours for actual slots.
export const slotHours = (openHour: number, closeHour: number) => {
	// The closing hour is bookable, but hour 24 (midnight) is not a real slot — the server clamps to 23.
	const last = Math.min(closeHour, 23);
	return Array.from({ length: closeHour > openHour ? last - openHour + 1 : 0 }, (_, i) => openHour + i);
};

// "9 AM, 10 AM … 5 PM · 9 slots a day"
export function slotPreview(openHour: number, closeHour: number) {
	const hours = slotHours(openHour, closeHour).map(hourText);
	if (!hours.length) return '';
	const list = hours.length > 3 ? `${hours[0]}, ${hours[1]} … ${hours[hours.length - 1]}` : hours.join(', ');
	return `${list} · ${hours.length} ${hours.length === 1 ? 'slot' : 'slots'} a day`;
}

export function hoursIssue(openHour: number, closeHour: number, openWeekdays?: number[]) {
	if (closeHour <= openHour) return 'Closing time must be after opening time.';
	if (openWeekdays && !openWeekdays.length) return 'Pick at least one open day.';
	return '';
}

// Visits that are open under the old hours but would fall outside the new ones, in date and hour order.
export function visitsOutside(visits: OutsideBooking[], before: (date: string) => DayHours, after: (date: string) => DayHours) {
	return visits
		.filter(visit => before(visit.date).hours.includes(visit.hour) && !after(visit.date).hours.includes(visit.hour))
		.sort((a, b) => a.date.localeCompare(b.date) || a.hour - b.hour);
}

// Which hours apply to a date: its own choice first, then the open weekdays with the default hours.
export function hoursForDate(settings: ScheduleSettings, date: string, override: DateOverride = {}): DayHours {
	const own = override.ownOpen !== undefined && override.ownClose !== undefined;
	const open = !override.closed && (own || override.open || settings.openWeekdays.includes(new Date(date + 'T00:00:00Z').getUTCDay()));
	const openHour = own ? override.ownOpen! : settings.openHour;
	const closeHour = own ? override.ownClose! : settings.closeHour;
	return { closed: !open, openHour, closeHour, hours: open ? slotHours(openHour, closeHour) : [] };
}