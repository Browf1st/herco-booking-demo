export type ActivityModule = 'Booking' | 'Booking calendar' | 'Change requests' | 'Inventory' | 'HERCO Points' | 'Rewards program' | 'Redemptions' | 'Pricing' | 'Promotion' | 'Customers';

export type ActivityEvent = {
	id: string;
	at: string;
	actor: string;
	action: string;
	module?: ActivityModule;
	bookingId?: string;
	target?: string;
	detail?: string;
};

export function activityEvent(module: ActivityModule, action: string, fields: Pick<ActivityEvent, 'target' | 'detail' | 'bookingId'> = {}, actor = 'Demo admin'): ActivityEvent {
	return { id: crypto.randomUUID(), at: new Date().toISOString(), actor, module, action, ...fields };
}
