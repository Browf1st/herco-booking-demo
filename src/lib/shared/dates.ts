import { shop } from './config';

// Dates are plain YYYY-MM-DD strings in shop time, so a customer abroad still sees Manila days.
const TZ = 'Asia/Manila';
const utc = (d: string) => new Date(`${d}T00:00:00Z`);

export const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date());

export const currentShopTime = () => new Intl.DateTimeFormat('en-GB', { timeZone: TZ, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date());

export const nowHour = () =>
	Number(new Intl.DateTimeFormat('en-GB', { timeZone: TZ, hour: '2-digit', hourCycle: 'h23' }).format(new Date()));

export function addDays(d: string, n: number) {
	const t = utc(d);
	t.setUTCDate(t.getUTCDate() + n);
	return t.toISOString().slice(0, 10);
}

export const isOpenDay = (d: string) => shop.openDays.includes(utc(d).getUTCDay());

export const isBookableDate = (date: string) =>
	/^\d{4}-\d{2}-\d{2}$/.test(date) && date >= today() &&
	Number.isFinite(utc(date).getTime()) && utc(date).toISOString().slice(0, 10) === date;

export const upcoming = () => Array.from({ length: shop.dateStripDays }, (_, i) => addDays(today(), i));

export const fmtDate = (d: string, options: Intl.DateTimeFormatOptions = { weekday: 'long', month: 'long', day: 'numeric' }) =>
	utc(d).toLocaleDateString('en-PH', { timeZone: 'UTC', ...options });

// One drop-off slot per open hour, the last one at the closing hour (F-026: closing hour is bookable).
// Hour 24 (midnight close) is not a real slot — the server clamps the last slot to 23.
export const slots = Array.from(
	{ length: shop.closeHour > shop.openHour ? Math.min(shop.closeHour, 23) - shop.openHour + 1 : 0 },
	(_, i) => `${String(shop.openHour + i).padStart(2, '0')}:00`
);

export function fmtSlot(slot: string) {
	const [hour, minute] = slot.split(':');
	const h = Number(hour);
	return `${h % 12 || 12}:${minute} ${h < 12 ? 'AM' : 'PM'}`;
}
