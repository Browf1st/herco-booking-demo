// What a staff member may do on a booking. Only Pending and Booked bookings can be changed; the server checks again.
// Kept in its own file so screens can use it without loading the rest of booking-changes.ts.
// "pages" is the list of pages the staff member may open (from GET /api/staff/workspace). When it is given:
// Edit price also needs viewIncome and the Bookings or Booking history page; Add/Remove needs the Bookings page.
// The demo passes no pages and keeps the simpler grant-only rule.
export function editRights(status: string, actions: readonly string[] | undefined, pages?: readonly string[]) {
	const open = status === 'pending' || status === 'confirmed';
	const can = (action: string) => Boolean(actions?.includes(action));
	const onPage = (...names: string[]) => !pages || names.some((name) => pages.includes(name));
	return {
		price: open && can('adjustPrices') && (!pages || can('viewIncome')) && onPage('Bookings', 'Booking history'),
		services: open && can('editServices') && onPage('Bookings')
	};
}
