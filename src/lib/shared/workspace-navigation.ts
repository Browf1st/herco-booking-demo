export type WorkspaceAccess = { role: string; pages: string[]; actions: string[] };
export type WorkspacePath = '/reports' | '/admin' | '/admin?view=requests' | '/customers' |
	'/booking-history' |
	'/staff-points' | '/inventory' | '/pricing' | '/activity-log' | '/staff-access' | '/manual-booking' | '/manual-booking?walk-in=1' |
	'/my-bookings' | '/account';
export type WorkspaceLink = { label: string; href: WorkspacePath };

const roles = new Set(['staff', 'admin', 'restricted_admin', 'owner', 'superadmin']);
const sections: { page: string; label: string; href: WorkspacePath }[] = [
	{ page: 'Reports', label: 'Reports', href: '/reports' },
	{ page: 'Bookings', label: 'Bookings', href: '/admin' },
	{ page: 'Change requests', label: 'Change requests', href: '/admin?view=requests' },
	{ page: 'Booking history', label: 'Booking history', href: '/booking-history' },
	{ page: 'Customers', label: 'Customers', href: '/customers' },
	{ page: 'HERCO Points', label: 'HERCO Points', href: '/staff-points' },
	{ page: 'Inventory', label: 'Inventory', href: '/inventory' },
	{ page: 'Pricing', label: 'Pricing', href: '/pricing' },
	{ page: 'Activity log', label: 'Activity log', href: '/activity-log' },
	{ page: 'Staff Access', label: 'Staff access', href: '/staff-access' }
];

export function parseWorkspaceAccess(value: unknown): WorkspaceAccess | null {
	if (!value || typeof value !== 'object') return null;
	const candidate = value as Partial<WorkspaceAccess>;
	if (typeof candidate.role !== 'string' || !roles.has(candidate.role) ||
		!Array.isArray(candidate.pages) || candidate.pages.some(page => typeof page !== 'string') ||
		!Array.isArray(candidate.actions) || candidate.actions.some(action => typeof action !== 'string')) return null;
	return { role: candidate.role, pages: candidate.pages, actions: candidate.actions };
}

export function workspaceLinks(access: WorkspaceAccess): WorkspaceLink[] {
	const links = sections.filter(section => access.pages.includes(section.page) &&
		(section.page !== 'Staff Access' || (['owner', 'superadmin'].includes(access.role) && access.actions.includes('manageStaff'))))
		.map(({ label, href }) => ({ label, href }));
	if (access.pages.includes('Bookings') && access.actions.includes('createBooking')) {
		links.push({ label: 'Manual booking · Online', href: '/manual-booking' },
			{ label: 'Manual booking · Walk-in', href: '/manual-booking?walk-in=1' });
	}
	return links;
}

export function workspaceGroups(access: WorkspaceAccess): { label: string; links: WorkspaceLink[] }[] {
	const links = workspaceLinks(access);
	const bookingPaths = new Set<WorkspacePath>(['/admin', '/admin?view=requests', '/booking-history', '/manual-booking', '/manual-booking?walk-in=1']);
	if (access.role === 'owner' || access.role === 'superadmin') {
		// Demo Owner order: Reports, Accounts, Activity Log, then everything else under More.
		const ownerOrder: WorkspacePath[] = ['/reports', '/staff-access', '/activity-log'];
		const ownerLabels: Partial<Record<WorkspacePath, string>> = { '/staff-access': 'Accounts', '/activity-log': 'Activity Log' };
		const primary = new Set<WorkspacePath>(ownerOrder);
		return [
			...ownerOrder.flatMap(href => links.filter(link => link.href === href))
				.map(link => ({ label: ownerLabels[link.href] ?? link.label, links: [link] })),
			...(links.some(link => !primary.has(link.href)) ? [{ label: 'More', links: links.filter(link => !primary.has(link.href)) }] : [])
		];
	}
	return [
		...(links.some(link => bookingPaths.has(link.href)) ? [{ label: 'Booking', links: links.filter(link => bookingPaths.has(link.href)) }] : []),
		...links.filter(link => !bookingPaths.has(link.href)).map(link => ({ label: link.label, links: [link] }))
	];
}

export function workspaceLanding(access: WorkspaceAccess | null): WorkspacePath {
	if (!access) return '/my-bookings';
	const preferred = access.role === 'owner' || access.role === 'superadmin' ? '/reports' : '/admin';
	const links = workspaceLinks(access);
	return links.find(link => link.href === preferred)?.href ?? links[0]?.href ?? '/account';
}

export function notifyAccountChanged(): void {
	if (typeof window !== 'undefined') window.dispatchEvent(new Event('herco-account-changed'));
}
