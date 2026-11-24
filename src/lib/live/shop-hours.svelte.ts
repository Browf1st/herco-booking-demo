// The shop's public default hours from GET /api/shop-hours. Stays null while loading or on error,
// so screens keep showing their fallback text.
import { resolve } from '$app/paths';
import type { ScheduleSettings } from '../shared/schedule-hours';

export const liveShopHours = $state<{ value: ScheduleSettings | null }>({ value: null });
let loading: Promise<void> | undefined;

// Keep the fallback text unless the answer looks right.
function readHours(data: ScheduleSettings): ScheduleSettings | null {
	const { openHour, closeHour, openWeekdays } = data;
	return Number.isInteger(openHour) && Number.isInteger(closeHour) && Array.isArray(openWeekdays) && openWeekdays.length
		? { openHour, closeHour, openWeekdays } : null;
}

// Safe to call from several screens: one request is shared, and a failed one can be retried later.
export function loadShopHours() {
	loading ??= fetch(resolve('/api/shop-hours'), { headers: { accept: 'application/json' } })
		.then(async response => {
			if (!response.ok) throw new Error();
			liveShopHours.value = readHours(await response.json());
		})
		.catch(() => { loading = undefined; });
	return loading;
}
