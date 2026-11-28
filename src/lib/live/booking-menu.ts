// Which items the customer's Actions menu shows for one booking. No imports, so Node tests can load it.

export type MenuItem = 'reschedule' | 'cancel' | 'withdraw' | 'edit-service' | 'view-service';
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
	/** The shop re-priced the booking after inspection, so the customer can no longer edit services. */
	shopPriced?: boolean;
};

export const menuLabels: Record<MenuItem, string> = {
	reschedule: 'Reschedule', cancel: 'Cancel booking', withdraw: 'Withdraw request',
	'edit-service': 'Edit service', 'view-service': 'View service'
};

/**
 * Reschedule and Cancel: future Pending or Booked bookings with no open request.
 * Withdraw: only while a request is open.
 * Edit service: a future Pending/Booked booking the shop has not re-priced; otherwise View service (read-only).
 * The server decides again when anything is sent.
 */
export function menuItems(input: MenuInput): MenuItem[] {
	const open = input.status === 'pending' || input.status === 'confirmed';
	// Customers can edit a booking only while it is still pending (the server enforces this too);
	// once the shop confirms or re-prices it, the menu offers a read-only View service instead.
	const canEdit = input.status === 'pending' && input.future && input.visitHour !== null && !input.shopPriced;
	const items: MenuItem[] = [];
	if (input.requestsReady && input.hasOpenRequest) items.push('withdraw');
	else if (input.requestsReady && open && input.future && input.visitHour !== null) items.push('reschedule', 'cancel');
	items.push(canEdit ? 'edit-service' : 'view-service');
	return items;
}
