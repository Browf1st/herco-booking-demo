// Demo store: bookings live in this browser only, and this file is the one seam a real database replaces.
import { demoFans, proFeatures, shop, type Size } from './config';
import { addDays, isOpenDay, nowHour, slots, today, upcoming } from './dates';

export type Status = 'pending' | 'confirmed' | 'done' | 'cancelled';
export type Booking = {
	id: string;
	date: string;
	slot: string;
	serviceId: string;
	size: Size;
	bike: string;
	plateNumber?: string;
	customerId?: string;
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

const SCENARIO_VERSION = 2;

// Fictional scenarios cover the lifecycle without relying on real customer information.
function seed(): Booking[] {
	const open = upcoming().filter(isOpenDay);
	const examples: { name: string; bike: string; size: Size; serviceId: string; notes: string; status: Status; gcashRef: string }[] = [
		{ name: 'Demo · Alex', bike: 'Honda ADV160', size: 'small', serviceId: 'ceramic-glossy', notes: 'Glossy black panels. New request, payment reference still missing.', status: 'pending', gcashRef: '' },
		{ name: 'Demo · Bea', bike: 'Yamaha NMAX 155', size: 'small', serviceId: 'ceramic-matte', notes: 'Keep the original matte finish. Payment reference supplied for staff review.', status: 'pending', gcashRef: 'DEMO-REF-1002' },
		{ name: 'Demo · Carlo', bike: 'Honda PCX160', size: 'small', serviceId: 'wheel-colour', notes: 'Purple rims. Booking confirmed after payment review.', status: 'confirmed', gcashRef: 'DEMO-REF-1003' },
		{ name: 'Demo · Dani', bike: 'Kawasaki Ninja 400', size: 'medium', serviceId: 'ceramic-glossy', notes: 'Customer cancelled. This slot is available for another rider.', status: 'cancelled', gcashRef: '' },
		{ name: 'Demo · Eli', bike: 'Yamaha Aerox 155', size: 'small', serviceId: 'wheel-colour', notes: 'Red wheel finish. Customer requests an assessment of both rims.', status: 'pending', gcashRef: '' },
		{ name: 'Demo · Fran', bike: 'Honda CB650R', size: 'large', serviceId: 'ceramic-glossy', notes: 'Rescheduled visit. Glossy tank and painted panels.', status: 'confirmed', gcashRef: 'DEMO-REF-1006' }
	];
	const rows = [6, slots.length, 3].flatMap((count, day) =>
		slots.slice(0, count).map((slot, i): Booking => {
			const example = examples[(i + day) % examples.length];
			const fanIndex = (i + day) % demoFans.length;
			return {
				...example,
				name: demoFans[fanIndex].name,
				customerId: 'DEMO-FAN-' + (fanIndex + 1),
				id: `HG-DEMO-${day + 1}${String(i + 1).padStart(2, '0')}`,
				date: open[day], slot,
				plateNumber: i % 3 === 0 ? '' : `DEMO ${day + 1}${i + 1}`,
				phone: '09000000000',
				email: `demo-rider-${day}-${i}@example.com`,
				status: day === 1 ? 'confirmed' : example.status,
				notes: day === 1 ? 'Busy day scenario. Confirmed booking, awaiting service.' : example.notes
			};
		})
	);
	const previousOpen = Array.from({ length: 7 }, (_, i) => addDays(today(), -i - 1)).find(isOpenDay)!;
	rows.push({
		...rows[0], id: 'HG-DEMO-COMPLETE', date: previousOpen, status: 'done',
		name: demoFans[0].name, customerId: 'DEMO-FAN-1', bike: 'Honda ADV160', notes: 'Completed glossy ceramic coating. Ready for staff to review points eligibility.', gcashRef: 'DEMO-REF-0901'
	});
	return rows;
}

function load(): { bookings: Booking[]; blocked: string[]; scenarioVersion: number } {
	const saved = typeof localStorage === 'undefined' ? null : localStorage.getItem(KEY);
	if (!saved) return { bookings: seed(), blocked: [], scenarioVersion: SCENARIO_VERSION };
	const stored = JSON.parse(saved);
	if (stored.scenarioVersion === SCENARIO_VERSION) return stored;
	if (stored.scenarioVersion === 1) {
		stored.bookings = stored.bookings.map((booking: Booking) => {
			const match = /^HG-DEMO-([1-3])(\d{2})$/.exec(booking.id);
			if (!match && booking.id !== 'HG-DEMO-COMPLETE') return booking;
			const index = match ? (Number(match[1]) + Number(match[2]) - 2) % demoFans.length : 0;
			return { ...booking, name: demoFans[index].name, customerId: 'DEMO-FAN-' + (index + 1) };
		});
		stored.scenarioVersion = SCENARIO_VERSION;
		localStorage.setItem(KEY, JSON.stringify(stored));
		return stored;
	}
	const retained: Booking[] = stored.bookings.filter((b: Booking) => !(/^Sample Rider \d+$/.test(b.name) && /^Sample bike \d+$/.test(b.bike)));
	const samples = seed().filter((sample) => !retained.some((b) => b.date === sample.date && b.slot === sample.slot && b.status !== 'cancelled'));
	const migrated = { bookings: [...retained, ...samples], blocked: stored.blocked ?? [], scenarioVersion: SCENARIO_VERSION };
	localStorage.setItem(KEY, JSON.stringify(migrated));
	return migrated;
}

export const db = $state(load());
const save = () => localStorage.setItem(KEY, JSON.stringify(db));

export const features = () => proFeatures;

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
