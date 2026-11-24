// Turns the shop's default hours into short public text, e.g. "Wed to Sun, 9 AM to 5 PM".
import { hourText, weekdayChoices, type ScheduleSettings } from './schedule-hours.ts';

// Runs of 3 or more days in the week (Mon to Sun) become "A to B"; shorter runs are listed.
// The week does not wrap, so Sat, Sun, Mon reads "Mon, Sat, Sun".
export function formatDays(weekdays: number[]) {
	const open = weekdayChoices.filter(choice => weekdays.includes(choice.day));
	if (open.length === 7) return 'Every day';
	const parts: string[] = [];
	for (let start = 0; start < open.length;) {
		let end = start;
		while (end + 1 < open.length && weekdayChoices.indexOf(open[end + 1]) === weekdayChoices.indexOf(open[end]) + 1) end++;
		const names = open.slice(start, end + 1).map(choice => choice.label);
		parts.push(names.length >= 3 ? `${names[0]} to ${names[names.length - 1]}` : names.join(', '));
		start = end + 1;
	}
	return parts.join(', ');
}

export function formatShopHours({ openHour, closeHour, openWeekdays }: ScheduleSettings) {
	const days = formatDays(openWeekdays);
	const hours = `${hourText(openHour)} to ${hourText(closeHour)}`;
	return { days, hours, text: `${days}, ${hours}` };
}

// The days the shop is closed ("Mon, Tue"), or "" when it is open every day.
export function formatClosedDays(openWeekdays: number[]) {
	const closed = weekdayChoices.map(choice => choice.day).filter(day => !openWeekdays.includes(day));
	return closed.length ? formatDays(closed) : '';
}
