export const adminTabs = ['Booking', 'Customers', 'HERCO Points', 'Inventory', 'Reports', 'Pricing', 'Activity log'] as const;
export const bookingSections = ['Bookings', 'Change requests', 'Booking history'] as const;

export function adminNavigation(params: Pick<URLSearchParams, 'get'>) {
	// Demo navigation only. Production must independently authorize every route,
	// query and mutation with trusted role/action grants, never the `view` parameter.
	const requested = params.get('tab');
	const owner = params.get('view') === 'owner';
	const tab = adminTabs.find(value => value === requested && (owner || value !== 'Activity log')) ?? (requested === 'Customers & points' ? 'HERCO Points' : 'Booking');
	const section = bookingSections.find(value => value === params.get('section')) ??
		bookingSections.find(value => value === requested) ?? 'Bookings';
	return { tab, section, owner };
}

export function adminPath(tab: string, owner: boolean, section?: string) {
	return `/admin?tab=${encodeURIComponent(tab)}${owner ? '&view=owner' : ''}${section ? '&section=' + encodeURIComponent(section) : ''}` as const;
}
