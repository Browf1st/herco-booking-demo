// Small helpers shared by the staff Reports, Bookings and Booking history screens (demo and live).

export type RecordStatus = 'pending' | 'confirmed' | 'done' | 'cancelled';

export const statusLabels: Record<RecordStatus, string> = { pending: 'Pending', confirmed: 'Booked', done: 'Completed', cancelled: 'Cancelled' };
/** A shape next to the colour, so status never relies on colour alone. */
export const statusIcons = { pending: 'clock', confirmed: 'calendar', done: 'check', cancelled: 'block' } as const;
/** The CSS badge colours call a confirmed booking "booked". */
export const badgeStatus = (status: RecordStatus) => (status === 'confirmed' ? 'booked' : status);

export type Period = { value: string; label: string };
export type RecordFilters = { preset: string; from: string; through: string; exact: string; search: string; status: string; source: string };

/** How many of the filters hidden behind "Filters (n)" are changed. The period chips are always visible, so they are not counted. */
export function activeFilterCount(filters: Pick<RecordFilters, 'search' | 'status' | 'source'>, includeStatus = true, includeSearch = true): number {
	return (includeSearch && filters.search.trim() ? 1 : 0) + (includeStatus && filters.status !== 'all' ? 1 : 0) + (filters.source !== 'all' ? 1 : 0);
}

/** Plain-words problem with the chosen dates, or '' when the dates are fine. */
export function rangeIssue(filters: Pick<RecordFilters, 'preset' | 'from' | 'through' | 'exact'>): string {
	if (filters.preset === 'date') return filters.exact ? '' : 'Choose an appointment date.';
	if (filters.preset !== 'custom') return '';
	if (!filters.from || !filters.through || filters.from > filters.through) return 'Choose both dates, with the end date on or after the start date.';
	// Same limit as the server: at most 365 days apart (366 counted inclusively). Date-only strings parse as UTC.
	return Date.parse(filters.through) - Date.parse(filters.from) <= 3.1536e10 ? '' : 'Choose a date range of up to 366 days.';
}

/** "Honda Click · 2 services". Leaves out whatever is missing. */
export function servicesLine(bike: string | undefined, count: number): string {
	const services = count > 0 ? count + (count === 1 ? ' service' : ' services') : '';
	return [bike?.trim(), services].filter(Boolean).join(' · ');
}
