import { resolve } from '$app/paths';

export function trackShopEvent(name: 'booking_started' | 'service_selected' | 'booking_submitted' | 'change_request_submitted') {
	void fetch(resolve('/api/analytics'), {
		method: 'POST', body: name, keepalive: true, headers: { 'content-type': 'text/plain' }
	}).catch(() => {});
}
