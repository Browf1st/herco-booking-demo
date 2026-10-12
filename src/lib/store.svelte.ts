// Demo store: bookings live in this browser only, and this file is the one seam a real database replaces.
import { services, shop, tiers, type Size, type Tier } from './config';
import { isOpenDay, nowHour, slots, today, upcoming } from './dates';

export type Status = 'pending' | 'confirmed' | 'done' | 'cancelled';
export type Booking = {
	id: string;
	date: string;
	slot: string;
	serviceId: string;
	size: Size;
	bike: string;
	name: string;
	phone: string;
	email: string;
	notes: string;
	gcashRef: string;
	status: Status;
};
export type NewBooking = Omit<Booking, 'id' | 'status'>;

const KEY = 'herco-demo-v1';
const code = () => `HG-${Math.random().toString(36).slice(2, 7).toUpperCase()}`;

// Seeds made-up bookings so the queue has a busy day, a full day and a quiet day to show.
function seed(): Booking[] {
	const open = upcoming().filter(isOpenDay);
	const sizes: Size[] = ['small', 'medium', 'large'];
	return [5, slots.length, 2].flatMap((count, day) =>
		slots.slice(0, count).map((slot, i) => ({
			id: code(),
			date: open[day],
			slot,
			serviceId: services[(i + day) % services.length].id,
			size: sizes[i % 3],
			bike: `Sample bike ${i + 1}`,
			name: `Sample Rider ${i + 1}`,
			phone: '09000000000',
			email: `rider${i + 1}@example.com`,
			notes: '',
			gcashRef: '0000000000000',
			status: day === 1 || i < 2 ? 'confirmed' : 'pending'
		}))
	);
}

function load(): { bookings: Booking[]; blocked: string[]; tier: Tier } {
	const saved = typeof localStorage === 'undefined' ? null : localStorage.getItem(KEY);
	return saved ? JSON.parse(saved) : { bookings: seed(), blocked: [], tier: 'pro' };
}

export const db = $state(load());
const save = () => localStorage.setItem(KEY, JSON.stringify(db));

export const features = () => tiers[db.tier];

export const bookingsOn = (date: string) =>
	db.bookings.filter((b) => b.date === date && b.status !== 'cancelled');

export function slotsFor(date: string) {
	const taken = new Set(bookingsOn(date).map((b) => b.slot));
	const past = date === today() ? nowHour() : -1;
	return slots.map((time) => ({ time, free: !taken.has(time) && parseInt(time) > past }));
}

export const spotsLeft = (date: string) =>
	Math.min(shop.dailyLimit - bookingsOn(date).length, slotsFor(date).filter((s) => s.free).length);

export function dayStatus(date: string) {
	if (!isOpenDay(date)) return 'closed';
	if (db.blocked.includes(date)) return 'blocked';
	return spotsLeft(date) > 0 ? 'open' : 'full';
}

// The real build enforces this with a unique index in Postgres, not in the browser.
function assertFree(date: string, slot: string) {
	if (dayStatus(date) !== 'open' || !slotsFor(date).find((s) => s.time === slot)?.free)
		throw new Error('That slot was just taken. Please pick another.');
}

export function book(input: NewBooking) {
	assertFree(input.date, input.slot);
	const booking: Booking = { ...input, id: code(), status: 'pending' };
	db.bookings.push(booking);
	save();
	return booking;
}

export function reschedule(id: string, date: string, slot: string) {
	assertFree(date, slot);
	Object.assign(db.bookings.find((b) => b.id === id)!, { date, slot });
	save();
}

export function setStatus(id: string, status: Status) {
	db.bookings.find((b) => b.id === id)!.status = status;
	save();
}

export function toggleBlock(date: string) {
	db.blocked = db.blocked.includes(date) ? db.blocked.filter((d) => d !== date) : [...db.blocked, date].sort();
	save();
}

export function setTier(tier: Tier) {
	db.tier = tier;
	save();
}

export function resetDemo() {
	db.bookings = seed();
	db.blocked = [];
	save();
}
