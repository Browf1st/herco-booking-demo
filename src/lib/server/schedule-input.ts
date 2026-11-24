/** Input rules for opening hours. The database checks the real hours of each date again on every save. */

/** A visit hour is a whole hour of the day, 0 (12 AM) to 23 (11 PM). */
export const isVisitHour = (value: unknown): value is number =>
	typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 23;

const isOpenHour = isVisitHour;
const isCloseHour = (value: unknown): value is number =>
	typeof value === 'number' && Number.isInteger(value) && value >= 1 && value <= 24;

export type ScheduleSettingsInput = {
	openHour: number;
	closeHour: number;
	openWeekdays: number[];
	confirmOutside: boolean;
	/** The settings version the staff member saw (from GET). Null when not sent. */
	version: string | null;
	/** How many outside bookings the staff member saw when confirming. Null when not sent. */
	confirmedOutsideCount: number | null;
};

const confirmedCountMessage = 'Check the confirmation count.';

/** Optional `confirmedOutsideCount`: a whole number from 0 up. Returns null when absent, undefined when invalid. */
function readConfirmedCount(value: unknown): number | null | undefined {
	if (value === undefined || value === null) return null;
	return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 1_000_000 ? value : undefined;
}

/** Returns the checked settings, or the message to show with a 400. */
export function parseScheduleSettings(body: unknown): { value: ScheduleSettingsInput } | { message: string } {
	const input = (body && typeof body === 'object' ? body : {}) as Record<string, unknown>;
	if (!isOpenHour(input.openHour) || !isCloseHour(input.closeHour)) return { message: 'Choose an opening and closing hour.' };
	if (input.closeHour <= input.openHour) return { message: 'Closing time must be after opening time.' };
	const days = input.openWeekdays;
	if (!Array.isArray(days) || days.length < 1 || days.length > 7 ||
		days.some(day => typeof day !== 'number' || !Number.isInteger(day) || day < 0 || day > 6) ||
		new Set(days).size !== days.length) return { message: 'Pick at least one open day.' };
	if (input.confirmOutside !== undefined && typeof input.confirmOutside !== 'boolean') return { message: 'Check the confirmation choice.' };
	const confirmedOutsideCount = readConfirmedCount(input.confirmedOutsideCount);
	if (confirmedOutsideCount === undefined) return { message: confirmedCountMessage };
	if (input.version !== undefined && input.version !== null && (typeof input.version !== 'string' || input.version.length < 1 || input.version.length > 40)) {
		return { message: 'Check the opening hours version.' };
	}
	return {
		value: {
			openHour: input.openHour, closeHour: input.closeHour, openWeekdays: [...days].sort((a, b) => a - b),
			confirmOutside: input.confirmOutside === true,
			version: typeof input.version === 'string' ? input.version : null,
			confirmedOutsideCount
		}
	};
}

/** Own hours for one date: same limits as the default hours. */
export function parseDateHours(body: unknown):
	{ value: { openHour: number; closeHour: number; confirmOutside: boolean; confirmedOutsideCount: number | null } } | { message: string } {
	const input = (body && typeof body === 'object' ? body : {}) as Record<string, unknown>;
	if (!isOpenHour(input.openHour) || !isCloseHour(input.closeHour)) return { message: 'Choose an opening and closing hour.' };
	if (input.closeHour <= input.openHour) return { message: 'Closing time must be after opening time.' };
	if (input.confirmOutside !== undefined && typeof input.confirmOutside !== 'boolean') return { message: 'Check the confirmation choice.' };
	const confirmedOutsideCount = readConfirmedCount(input.confirmedOutsideCount);
	if (confirmedOutsideCount === undefined) return { message: confirmedCountMessage };
	return { value: { openHour: input.openHour, closeHour: input.closeHour, confirmOutside: input.confirmOutside === true, confirmedOutsideCount } };
}
