import { shop } from './config';

// Dates are plain YYYY-MM-DD strings in shop time, so a customer abroad still sees Manila days.
const TZ = 'Asia/Manila';
const utc = (d: string) => new Date(`${d}T00:00:00Z`);

export const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date());

export const nowHour = () =>
	Number(new Intl.DateTimeFormat('en-GB', { timeZone: TZ, hour: '2-digit', hourCycle: 'h23' }).format(new Date()));

export function addDays(d: string, n: number) {
	const t = utc(d);
	t.setUTCDate(t.getUTCDate() + n);
	return t.toISOString().slice(0, 10);
}

export const isOpenDay = (d: string) => shop.openDays.includes(utc(d).getUTCDay());

export const upcoming = () => Array.from({ length: shop.bookingWindowDays }, (_, i) => addDays(today(), i));

export const fmtDate = (d: string, options: Intl.DateTimeFormatOptions = { weekday: 'long', month: 'long', day: 'numeric' }) =>
	utc(d).toLocaleDateString('en-PH', { timeZone: 'UTC', ...options });

// One drop-off slot per open hour, the last one an hour before closing.
export const slots = Array.from(
	{ length: shop.closeHour - shop.openHour },
	(_, i) => `${String(shop.openHour + i).padStart(2, '0')}:00`
);

export function fmtSlot(slot: string) {
	const h = parseInt(slot);
	return `${h % 12 || 12}:00 ${h < 12 ? 'AM' : 'PM'}`;
}
