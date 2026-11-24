// Staff Access form (owner item 13, 2026-11-23). One action can belong to more than one page
// (e.g. "Complete bookings and attach photos" is on Bookings and Booking history). The form must
// list each action once: a repeated key crashed the keyed list and stopped the form from saving.
export type StaffGrant = { page: string; key: string; label: string };

/** The actions a person has, grouped by the page they belong to (catalog order, each key once). Unknown keys go under "Other". */
export function groupGrantedActions(grants: readonly StaffGrant[], keys: readonly string[]): { page: string; labels: string[] }[] {
	const groups = new Map<string, string[]>();
	const done = new Set<string>();
	const add = (page: string, label: string) => groups.set(page, [...(groups.get(page) ?? []), label]);
	for (const grant of grants) {
		if (!keys.includes(grant.key) || done.has(grant.key)) continue;
		done.add(grant.key);
		add(grant.page, grant.label);
	}
	for (const key of keys) if (!done.has(key)) { done.add(key); add('Other', key); }
	return [...groups].map(([page, labels]) => ({ page, labels }));
}

/** Actions for the ticked pages, each key once, in catalog order (first matching page wins). */
export function visibleActions(actions: readonly StaffGrant[], pages: readonly string[]): StaffGrant[] {
	const seen = new Set<string>();
	return actions.filter((action) => {
		if (!pages.includes(action.page) || seen.has(action.key)) return false;
		seen.add(action.key);
		return true;
	});
}
