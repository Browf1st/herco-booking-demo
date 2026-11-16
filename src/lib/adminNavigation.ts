export const adminTabs = ['Booking', 'Customers', 'HERCO Points', 'Inventory', 'Reports', 'Pricing', 'Activity log'] as const;
export const bookingSections = ['Overview', 'Bookings', 'Change requests', 'Booking history'] as const;

export function adminNavigation(params: Pick<URLSearchParams, 'get'>) {
	const requested = params.get('tab');
	const tab = adminTabs.find(value => value === requested) ?? (requested === 'Customers & points' ? 'HERCO Points' : 'Booking');
	const section = bookingSections.find(value => value === params.get('section')) ??
		bookingSections.find(value => value === requested) ?? 'Overview';
	return { tab, section };
}
