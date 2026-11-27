// Which items the customer's Actions menu shows for one booking. No imports, so Node tests can load it.

export type MenuItem = 'reschedule' | 'cancel' | 'withdraw' | 'details';
export type MenuInput = {
	status: string;
	/** null for a walk-in, which cannot be changed online. */
	visitHour: number | null;
	/** The visit is still in the future. */
	future: boolean;
	/** The cancel/reschedule request check finished (request buttons stay hidden until it does). */
	requestsReady: boolean;
	/** An open cancel or reschedule request exists. */
	hasOpenRequest: boolean;
};

export const menuLabels: Record<MenuItem, string> = {
	reschedule: 'Reschedule', cancel: 'Cancel booking', withdraw: 'Withdraw request', details: 'View details'
};

/**
 * Reschedule and Cancel: future Pending or Booked bookings with no open request.
 * Withdraw: only while a request is open. View details: always.
 * The server decides again when anything is sent.
 */
export function menuItems(input: MenuInput): MenuItem[] {
	const open = input.status === 'pending' || input.status === 'confirmed';
	const items: MenuItem[] = [];
	if (input.requestsReady && input.hasOpenRequest) items.push('withdraw');
	else if (input.requestsReady && open && input.future && input.visitHour !== null) items.push('reschedule', 'cancel');
	items.push('details');
	return items;
}
