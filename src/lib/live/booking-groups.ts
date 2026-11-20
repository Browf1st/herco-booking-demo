// Sorts a customer's bookings into the My Bookings sections. No imports, so Node tests can load it.

export type BookingGroup = 'upcoming' | 'requests' | 'past' | 'cancelled';
type Groupable = { id: string; status: string; visit_date: string; visit_hour: number | null };

export const bookingGroupOrder: readonly BookingGroup[] = ['upcoming', 'requests', 'past', 'cancelled'];
export const bookingGroupLabels: Record<BookingGroup, string> = {
	upcoming: 'Upcoming', requests: 'Requests', past: 'Past', cancelled: 'Cancelled'
};
export const bookingGroupEmpty: Record<BookingGroup, string> = {
	upcoming: 'No upcoming visits on this page.',
	requests: 'No open cancel or reschedule requests on this page.',
	past: 'No past visits on this page.',
	cancelled: 'No cancelled bookings on this page.'
};

/**
 * Completed visits, and visits whose date has passed but the shop has not marked done, go under Past.
 * A future booking with an open change request goes under Requests until the shop decides.
 */
export function bookingGroup(booking: Groupable, hasPendingRequest: boolean, isFuture: boolean): BookingGroup {
	if (booking.status === 'cancelled') return 'cancelled';
	if (booking.status === 'done' || !isFuture) return 'past';
	return hasPendingRequest ? 'requests' : 'upcoming';
}

const visitKey = (booking: Groupable) => booking.visit_date + String(booking.visit_hour ?? 0).padStart(2, '0');

/** Upcoming and Requests show the soonest visit first; Past shows the latest visit first; Cancelled keeps the newest-first order. */
export function groupBookings<T extends Groupable>(
	bookings: readonly T[], pendingBookingIds: ReadonlySet<string>, isFuture: (booking: T) => boolean
) {
	const groups: Record<BookingGroup, T[]> = { upcoming: [], requests: [], past: [], cancelled: [] };
	for (const booking of bookings) groups[bookingGroup(booking, pendingBookingIds.has(booking.id), isFuture(booking))].push(booking);
	for (const name of ['upcoming', 'requests'] as const) groups[name].sort((a, b) => visitKey(a).localeCompare(visitKey(b)));
	groups.past.sort((a, b) => visitKey(b).localeCompare(visitKey(a)));
	return groups;
}

/** Opens the section of a just-submitted booking, or the first section that has bookings. */
export function initialGroup<T extends Groupable>(groups: Record<BookingGroup, T[]>, focusId = ''): BookingGroup {
	const focused = bookingGroupOrder.find(name => groups[name].some(booking => booking.id === focusId));
	return focused ?? bookingGroupOrder.find(name => groups[name].length) ?? 'upcoming';
}
