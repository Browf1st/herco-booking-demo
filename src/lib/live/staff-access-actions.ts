// Staff Access form (owner item 13, 2026-11-23). One action can belong to more than one page
// (e.g. "Complete bookings and attach photos" is on Bookings and Booking history). The form must
// list each action once: a repeated key crashed the keyed list and stopped the form from saving.
export type StaffGrant = { page: string; key: string; label: string };

/** Actions for the ticked pages, each key once, in catalog order (first matching page wins). */
export function visibleActions(actions: readonly StaffGrant[], pages: readonly string[]): StaffGrant[] {
	const seen = new Set<string>();
	return actions.filter((action) => {
		if (!pages.includes(action.page) || seen.has(action.key)) return false;
		seen.add(action.key);
		return true;
	});
}
