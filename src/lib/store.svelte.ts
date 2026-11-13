// Demo store: bookings live in this browser only, and this file is the one seam a real database replaces.
import { demoFans, proFeatures, shop, type Size } from './config';
import { defaultPricing, selection, validateSelection, quote, type Selection, type Pricing } from './coating';
import { powderDay } from './bookingCatalog';
import { addDays, isOpenDay, nowHour, slots, today, upcoming } from './dates';

export type Status = 'pending' | 'confirmed' | 'done' | 'cancelled';
export type ChangeRequest = { kind: 'Cancel' | 'Reschedule'; reason: string; date?: string; slot?: string; state: 'Pending' | 'Approved' | 'Declined'; at: string; reviewedAt?: string };
type Event = { id: string; at: string; actor: string; action: string; bookingId?: string };
type DemoData = { bookings: Booking[]; blocked: string[]; opened?: string[]; blockedSlots?: Record<string, string[]>; scenarioVersion: number; pricing?: Pricing; events?: Event[] };
type ServiceSnapshot = { selection: Selection; estimate?: ReturnType<typeof quote> };
type ServiceChange = { id: string; at: string; actor: string; before: ServiceSnapshot; after: ServiceSnapshot };
export type Booking = {
 originalServices?: ServiceSnapshot;
 serviceChanges?: ServiceChange[];
 selection?: Selection;
 estimate?: ReturnType<typeof quote>;
 accountId?: string;
 requests?: ChangeRequest[];
 approvalNote?: string;
 completionNote?: string;
 photos?: string[];
 completedAt?: string;
 walkIn?: { signer: string; at: string; version: string; immediate?: boolean };
	id: string;
	date: string;
	slot: string;
	serviceId: string;
	size?: Size;
	finish?: string;
	bike: string;
	plateNumber?: string;
	modelYear?: number;
	customerId?: string;
	name: string;
	phone: string;
	email: string;
	notes: string;
	status: Status;
};
export type NewBooking = Omit<Booking, 'id' | 'status'>;

const KEY = 'herco-demo-v1';
const code = () => `HG-${Math.random().toString(36).slice(2, 7).toUpperCase()}`;

const SCENARIO_VERSION = 2;

// Fictional scenarios cover the lifecycle without relying on real customer information.
function seed(): Booking[] {
	const open = upcoming().filter(isOpenDay);
	const examples: { name: string; bike: string; size: Size; serviceId: string; notes: string; status: Status }[] = [
		{ name: 'Demo · Alex', bike: 'Honda ADV160', size: 'small', serviceId: 'ceramic-glossy', notes: 'Glossy black panels.', status: 'pending' },
		{ name: 'Demo · Bea', bike: 'Yamaha NMAX 155', size: 'small', serviceId: 'ceramic-matte', notes: 'Keep the original matte finish.', status: 'pending' },
		{ name: 'Demo · Carlo', bike: 'Honda PCX160', size: 'small', serviceId: 'wheel-colour', notes: 'Purple rims.', status: 'confirmed' },
		{ name: 'Demo · Dani', bike: 'Kawasaki Ninja 400', size: 'medium', serviceId: 'ceramic-glossy', notes: 'Customer cancelled. This slot is available for another rider.', status: 'cancelled' },
		{ name: 'Demo · Eli', bike: 'Yamaha Aerox 155', size: 'small', serviceId: 'wheel-colour', notes: 'Red wheel finish. Customer requests an assessment of both rims.', status: 'pending' },
		{ name: 'Demo · Fran', bike: 'Honda CB650R', size: 'large', serviceId: 'ceramic-glossy', notes: 'Rescheduled visit. Glossy tank and painted panels.', status: 'confirmed' }
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
		name: demoFans[0].name, customerId: 'DEMO-FAN-1', bike: 'Honda ADV160', notes: 'Completed glossy ceramic coating. Ready for staff to review points eligibility.'
	});
	return rows;
}

function load(): DemoData {
	const saved = typeof localStorage === 'undefined' ? null : localStorage.getItem(KEY);
	if (!saved) return { bookings: seed(), blocked: [], scenarioVersion: SCENARIO_VERSION };
	const stored = JSON.parse(saved);
	let cleaned = false;
	for (const booking of stored.bookings) {
		if ('gcashRef' in booking) {
			delete booking.gcashRef;
			cleaned = true;
		}
		if (booking.id.startsWith('HG-DEMO-')) {
			const notes = booking.notes.replace(/ (New request, payment reference still missing|Payment reference supplied for staff review|Booking confirmed after payment review)\.$/, '');
			cleaned ||= notes !== booking.notes;
			booking.notes = notes;
		}
	}
	if (cleaned) localStorage.setItem(KEY, JSON.stringify(stored));
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
	const migrated = { bookings: [...retained, ...samples], blocked: stored.blocked ?? [], opened: stored.opened ?? [], blockedSlots: stored.blockedSlots ?? {}, scenarioVersion: SCENARIO_VERSION };
	localStorage.setItem(KEY, JSON.stringify(migrated));
	return migrated;
}

export const sampleServiceBookingId = 'HG-DEMO-SERVICE-ADDON';
const sampleOriginal = selection();
const sampleCurrent = { ...sampleOriginal, powder: true, powderParts: ['Brackets'], finish: 'Satin bronze' };
const sampleBefore = { selection: sampleOriginal, estimate: quote(sampleOriginal, 'small', 'Honda ADV160', defaultPricing) };
const sampleAfter = { selection: sampleCurrent, estimate: quote(sampleCurrent, 'small', 'Honda ADV160', defaultPricing) };
const sampleBooking: Booking = {
 id: sampleServiceBookingId, name: 'Sample · Jamie Reyes', bike: 'Honda ADV160', size: 'small',
 modelYear: 2025, date: addDays(today(), -1), slot: '10:00', status: 'done', serviceId: 'ceramic',
 phone: '', email: '', notes: 'Sample booking with an extra service requested at the shop.',
 selection: sampleCurrent, estimate: sampleAfter.estimate, originalServices: sampleBefore,
 serviceChanges: [{ id: 'sample-addon', at: addDays(today(), -1) + 'T02:30:00Z', actor: 'Demo admin', before: sampleBefore, after: sampleAfter }]
};
const loaded = load();
if (!loaded.bookings.some(booking => booking.id === sampleServiceBookingId)) loaded.bookings.push(sampleBooking);
export const db = $state({ ...loaded, opened: loaded.opened ?? [], blockedSlots: loaded.blockedSlots ?? {}, pricing: loaded.pricing ?? structuredClone(defaultPricing), events: loaded.events ?? [] });
const save = () => localStorage.setItem(KEY, JSON.stringify(db));

export function syncBookings() {
 const sync = (event: StorageEvent) => {
  if (event.key !== KEY || !event.newValue) return;
  const saved: DemoData = JSON.parse(event.newValue);
  Object.assign(db, { ...saved, opened: saved.opened ?? [], blockedSlots: saved.blockedSlots ?? {}, pricing: saved.pricing ?? structuredClone(defaultPricing), events: saved.events ?? [] });
 };
 window.addEventListener('storage', sync);
 return () => window.removeEventListener('storage', sync);
}

export function audit(action: string, bookingId?: string, actor = 'Demo admin') {
 db.events.push({ id: crypto.randomUUID(), at: new Date().toISOString(), actor, action, bookingId });
 save();
}

export function updatePricing(pricing: Pricing) {
 const amounts = [...Object.values(pricing.ceramic), ...Object.values(pricing.powder), ...Object.values(pricing.size), ...Object.values(pricing.models)];
 if (amounts.some(n => !Number.isFinite(n) || n < 0) || !Number.isFinite(pricing.promo) || pricing.promo < 0 || pricing.promo > 100) throw Error('Use nonnegative amounts and a promotion between 0 and 100%.');
 db.pricing = pricing;
 audit('Updated pricing and promotion (' + pricing.promo + '%)');
}

export function coatingOf(booking: Booking): Selection {
 if (booking.selection) return $state.snapshot(booking.selection);
 const powder = booking.serviceId === 'wheel-colour';
 return { ...selection(powder, booking.finish), ceramicFinish: booking.serviceId === 'ceramic-matte' ? 'Stay Matte' : 'Glossy Finish', powderParts: powder ? ['Wheels / mags'] : [], front: powder ? 'Not sure' : '' };
}

function active(booking: Booking) {
 if (booking.status !== 'pending' && booking.status !== 'confirmed') throw Error('This booking is already closed.');
}

export function editCoating(booking: Booking, input: Selection, actor = 'Demo admin') {
 active(booking);
 validateSelection(input, booking.bike);
 if (!booking.selection?.powder && !booking.walkIn?.immediate) assertServiceDay(input, booking.date);
 const before = { selection: coatingOf(booking), estimate: $state.snapshot(booking.estimate) };
 const estimate = estimateServiceEdit(booking, input);
 if (JSON.stringify(before.selection) === JSON.stringify(input)) return;
 const after = { selection: input, estimate };
 booking.serviceChanges = [...(booking.serviceChanges ?? []), { id: crypto.randomUUID(), at: new Date().toISOString(), actor, before, after }];
 booking.selection = input;
 booking.serviceId = input.ceramic ? 'ceramic' : 'wheel-colour';
 booking.estimate = estimate;
 audit('Updated services' + (before.estimate ? ' · ₱' + before.estimate.total + ' → ₱' + estimate.total : ''), booking.id, actor);
}

export function estimateServiceEdit(booking: Booking, input: Selection) {
 return quote(input, booking.size ?? 'small', booking.bike, db.pricing, $state.snapshot(booking.estimate?.lines), booking.modelYear);
}

export function requestChange(booking: Booking, kind: ChangeRequest['kind'], reason: string, date?: string, slot?: string) {
 active(booking);
 if (booking.requests?.some(r => r.state === 'Pending')) throw Error('There is already a request awaiting review.');
 if (kind === 'Reschedule') {
  assertServiceDay(booking.selection, date ?? '');
  assertFree(date ?? '', slot ?? '');
 }
 booking.requests = [...(booking.requests ?? []), { kind, reason, date, slot, state: 'Pending', at: new Date().toISOString() }];
 audit(kind + ' requested', booking.id, 'Customer');
}

export function reviewChange(booking: Booking, request: ChangeRequest, approved: boolean) {
 active(booking);
 if (request.state !== 'Pending') throw Error('This request has already been reviewed.');
 const previous = booking.date + ' ' + booking.slot;
 if (approved && request.kind === 'Reschedule') {
  assertServiceDay(booking.selection, request.date ?? '');
  assertFree(request.date ?? '', request.slot ?? '');
  booking.date = request.date!;
  booking.slot = request.slot!;
 }
 if (approved && request.kind === 'Cancel') booking.status = 'cancelled';
 request.state = approved ? 'Approved' : 'Declined';
 request.reviewedAt = new Date().toISOString();
 audit(request.kind + ' ' + request.state.toLowerCase() + (approved && request.kind === 'Reschedule' ? ' · ' + previous + ' → ' + booking.date + ' ' + booking.slot : ''), booking.id);
}

export function approveBooking(booking: Booking, note: string) {
 if (booking.status !== 'pending') throw Error('Only pending bookings can be confirmed.');
 booking.approvalNote = note;
 setStatus(booking.id, 'confirmed');
}

export function completeBooking(booking: Booking, note: string, photos: string[]) {
 if (booking.status !== 'confirmed') throw Error('Confirm this booking before completing it.');
 if (booking.requests?.some(r => r.state === 'Pending')) throw Error('Review the pending change request before completing this booking.');
 const previous = { completionNote: booking.completionNote, photos: booking.photos, completedAt: booking.completedAt, status: booking.status };
 Object.assign(booking, { completionNote: note, photos, completedAt: new Date().toISOString(), status: 'done' });
 try { audit('Confirmed → Done' + (photos.length ? ' · Added ' + photos.length + ' completion photo(s)' : ''), booking.id); }
 catch (error) { Object.assign(booking, previous); db.events.pop(); throw error; }
}

export const features = () => proFeatures;

export const bookingsOn = (date: string) =>
	db.bookings.filter((b) => b.date === date && b.status !== 'cancelled' && !b.walkIn?.immediate);

export function isSlotBlocked(date: string, time: string) {
	return db.blockedSlots[date]?.includes(time) ?? false;
}

export function toggleSlotBlock(date: string, time: string) {
	if (date < today() || !slots.includes(time)) throw Error('Choose a valid appointment time on today or a future date.');
	const blocked = isSlotBlocked(date, time);
	const previous = db.blockedSlots[date] ?? [];
	db.blockedSlots[date] = blocked ? previous.filter(slot => slot !== time) : [...previous, time];
	audit((blocked ? 'Unblocked ' : 'Blocked ') + date + ' at ' + time);
}

export function slotsFor(date: string) {
	const taken = new Set(bookingsOn(date).map((b) => b.slot));
	const past = date === today() ? nowHour() : -1;
	return slots.map((time) => ({ time, free: !isSlotBlocked(date, time) && !taken.has(time) && parseInt(time) > past }));
}

export const spotsLeft = (date: string) =>
	Math.min(shop.dailyLimit - bookingsOn(date).length, slotsFor(date).filter((s) => s.free).length);

export function dayStatus(date: string) {
	if (db.blocked.includes(date)) return 'blocked';
	if (!db.opened.includes(date) && !isOpenDay(date)) return 'closed';
	return spotsLeft(date) > 0 ? 'open' : 'full';
}

// The real build enforces this with a unique index in Postgres, not in the browser.
function assertFree(date: string, slot: string) {
	if (!upcoming().includes(date) || dayStatus(date) !== 'open' || !slotsFor(date).find((s) => s.time === slot)?.free)
		throw new Error('That slot was just taken. Please pick another.');
}

function assertServiceDay(selection: Selection | undefined, date: string) {
	if (selection?.catalog && selection.powder && !powderDay(date))
		throw Error('Choose a Wednesday, Saturday, or Sunday for powder coating.');
}

export function book(input: NewBooking) {
	if (!input.walkIn?.immediate) assertServiceDay(input.selection, input.date);
	if (!input.walkIn?.immediate) assertFree(input.date, input.slot);
	if (input.selection) validateSelection(input.selection, input.bike);
	const estimate = input.selection ? quote(input.selection, input.size ?? 'small', input.bike, db.pricing, [], input.modelYear) : undefined;
	const originalServices = input.selection ? { selection: structuredClone(input.selection), estimate: structuredClone(estimate) } : undefined;
	const booking: Booking = { ...input, estimate, originalServices, id: code(), status: 'pending' };
	db.bookings.push(booking);
	audit(input.walkIn ? 'Recorded walk-in intake' : 'Booking submitted · Pending', booking.id, input.walkIn ? 'Demo admin' : 'Customer');
	return booking;
}

export function reschedule(id: string, date: string, slot: string) {
	const booking = db.bookings.find(b => b.id === id)!;
	active(booking);
	assertServiceDay(booking.selection, date);
	assertFree(date, slot);
	if (booking.requests?.some(r => r.state === 'Pending')) throw Error('Review the pending change request first.');
	const previous = booking.date + ' ' + booking.slot;
	Object.assign(booking, { date, slot });
	if (booking.walkIn) booking.walkIn.immediate = false;
	audit('Rescheduled · ' + previous + ' → ' + date + ' ' + slot, id);
}

export function setStatus(id: string, status: Status) {
	const booking = db.bookings.find(b => b.id === id)!;
	active(booking);
	if (status === 'cancelled' && booking.requests?.some(r => r.state === 'Pending')) throw Error('Review the pending change request first.');
	const previous = booking.status;
	booking.status = status;
	audit(previous + ' → ' + status, id);
}

export function setDateAvailability(date: string, override: 'open' | 'closed' | 'regular') {
 if (date < today()) throw Error('Choose today or a future date.');
 db.blocked = db.blocked.filter(day => day !== date);
 db.opened = db.opened.filter(day => day !== date);
 if (override === 'closed') db.blocked.push(date);
 if (override === 'open') db.opened.push(date);
 const action = { open: 'Opened bookings', closed: 'Closed bookings', regular: 'Restored regular hours' };
 audit(action[override] + ' for ' + date);
}
