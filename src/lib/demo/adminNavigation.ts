import { bookingPages, canAccessPage, staffAccess } from './staffAccess.svelte.ts';

export const adminTabs = ['Booking', 'Customers', 'HERCO Points', 'Inventory', 'Reports', 'Pricing', 'Activity log', 'Staff Access'] as const;

export function adminNavigation(params: Pick<URLSearchParams, 'get'>) {
	const requested = params.get('tab');
	const tabs = adminTabs.filter(canAccessPage);
	const sections = bookingPages.filter(canAccessPage);
	const requestedSection = params.get('section') ?? (requested === 'Booking' ? null : requested);
	const section = bookingPages.find(value => value === requestedSection) ?? sections[0] ?? 'Bookings';
	const tab = adminTabs.find(value => value === requested) ??
		(requested === 'Customers & points' ? 'HERCO Points' : requested || params.get('section') ? 'Booking' : tabs[0] ?? 'Booking');
	const knownTab = requested === null || requested === 'Customers & points' ||
		adminTabs.some(value => value === requested) || bookingPages.some(value => value === requested);
	const knownSection = tab !== 'Booking' || !params.get('section') ||
		bookingPages.some(value => value === requestedSection);
	const allowed = knownTab && knownSection && canAccessPage(tab === 'Booking' ? section : tab);
	return { tab, section, owner: staffAccess.owner, allowed, tabs, sections };
}

export function adminPath(tab: string, section?: string) {
	return `/admin?tab=${encodeURIComponent(tab)}${section ? '&section=' + encodeURIComponent(section) : ''}` as const;
}
