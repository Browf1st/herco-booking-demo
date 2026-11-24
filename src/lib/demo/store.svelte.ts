import { activityEvent, type ActivityEvent, type ActivityModule } from './activity';
import { requireStaffAction, staffActor } from './staffAccess.svelte.ts';
// Demo store: bookings live in this browser only, and this file is the one seam a real database replaces.
// Production boundary: derive the actor from a verified session, validate input on the
// server, then commit capacity checks, saved prices, history and an email outbox in
// one database transaction. Never use this store or a URL role as authorization.
// See docs/production-plan.md for the staged Supabase/Brevo implementation.
import { demoFans, proFeatures, type Size } from '../shared/config';
import { applyServicePriceAdjustments, defaultPricing, olderPowderParts, selection, validateSelection, quote, type Selection, type Pricing } from '../shared/coating';
import { ceramicTierNames, defaultCeramicCatalogPricing, powderDay } from '../shared/bookingCatalog';
import { addDays, isBookableDate, isOpenDay, nowHour, slots, today, upcoming } from '../shared/dates';
import { defaultSettings, hoursForDate, type ScheduleSettings } from '../shared/schedule-hours';

export type Status = 'pending' | 'confirmed' | 'done' | 'cancelled';
export const bookingStatusLabels: Record<Status, string> = { pending: 'Pending', confirmed: 'Booked', done: 'Completed', cancelled: 'Cancelled' };
export const MAX_COMPLETION_PHOTOS = 3;
export type ChangeRequest = { kind: 'Cancel' | 'Reschedule'; reason: string; date?: string; slot?: string; state: 'Pending' | 'Approved' | 'Declined'; at: string; reviewedAt?: string };
type DemoData = { bookings: Booking[]; blocked: string[]; opened?: string[]; blockedSlots?: Record<string, string[]>; hours?: ScheduleSettings; dateHours?: Record<string, { openHour: number; closeHour: number }>; scenarioVersion: number; pricing?: Pricing; events?: ActivityEvent[] };
type ServiceSnapshot = { selection: Selection; estimate?: ReturnType<typeof quote> };
export type ServiceChange = { id: string; at: string; actor: string; before: ServiceSnapshot; after: ServiceSnapshot; reason?: string };
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
 createdAt?: string;
 approvedAt?: string;
 cancelledAt?: string;
 cancellationNote?: string;
 completedAt?: string;
 bookedByStaff?: boolean;
 finalPrice?: number;
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
	rows[0].requests = [{ kind: 'Cancel', reason: 'Demo: I can no longer make the appointment.', state: 'Pending', at: new Date().toISOString() }];
	if (open[3]) rows[1].requests = [{ kind: 'Reschedule', reason: 'Demo: Could I move my appointment to the next open day?', date: open[3], slot: slots[0], state: 'Pending', at: new Date().toISOString() }];
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
const sampleQuote = quote(sampleCurrent, 'small', 'Honda ADV160', defaultPricing);
const sampleAfter = { selection: sampleCurrent, estimate: applyServicePriceAdjustments(sampleQuote, { [sampleQuote.lines![0].label]: 1600 }) };
const sampleBooking: Booking = {
 id: sampleServiceBookingId, name: 'Sample · Jamie Reyes', bike: 'Honda ADV160', size: 'small',
 createdAt: addDays(today(), -4) + 'T03:00:00Z', approvedAt: addDays(today(), -3) + 'T02:00:00Z', completedAt: addDays(today(), -1) + 'T07:00:00Z',
 modelYear: 2025, date: addDays(today(), -1), slot: '10:00', status: 'done', serviceId: 'ceramic',
 phone: '', email: '', notes: 'Sample booking with an extra service requested at the shop.',
 selection: sampleCurrent, estimate: sampleAfter.estimate, originalServices: sampleBefore,
 serviceChanges: [{ id: 'sample-addon', at: addDays(today(), -1) + 'T02:30:00Z', actor: 'Demo admin', before: sampleBefore, after: sampleAfter }]
};
const demo = import.meta.env.MODE !== 'worker';
const loaded: DemoData = demo ? load() : { bookings: [], blocked: [], scenarioVersion: SCENARIO_VERSION };
if (demo && !loaded.bookings.some(booking => booking.id === sampleServiceBookingId)) loaded.bookings.push(sampleBooking);
// Final prices for the completed demo scenarios, including older saved copies.
const sampleFinalPrices = new Map([
 ['HG-DEMO-208', 2500],
 ['HG-DEMO-COMPLETE', sampleBefore.estimate.total],
 [sampleServiceBookingId, sampleAfter.estimate.total]
]);
let repairedSamplePrices = false;
for (const booking of loaded.bookings) {
 const price = sampleFinalPrices.get(booking.id);
 if (booking.status !== 'done' || booking.finalPrice !== undefined || price === undefined) continue;
 booking.finalPrice = price;
 repairedSamplePrices = true;
}
if (repairedSamplePrices && typeof localStorage !== 'undefined' && localStorage.getItem(KEY)) {
 localStorage.setItem(KEY, JSON.stringify(loaded));
}
const withHours = (data: DemoData) => ({ opened: data.opened ?? [], blockedSlots: data.blockedSlots ?? {}, hours: data.hours ?? defaultSettings(), dateHours: data.dateHours ?? {} });
export const db = $state({ ...loaded, ...withHours(loaded), pricing: loaded.pricing ?? structuredClone(defaultPricing), events: loaded.events ?? [] });
const save = () => localStorage.setItem(KEY, JSON.stringify(db));

export function syncBookings() {
 const sync = (event: StorageEvent) => {
  if (event.key !== KEY || !event.newValue) return;
  const saved: DemoData = JSON.parse(event.newValue);
  Object.assign(db, { ...saved, ...withHours(saved), pricing: saved.pricing ?? structuredClone(defaultPricing), events: saved.events ?? [] });
 };
 window.addEventListener('storage', sync);
 return () => window.removeEventListener('storage', sync);
}

export function audit(action: string, bookingId?: string, actor = staffActor(), module: ActivityModule = 'Booking', detail?: string) {
 db.events.push(activityEvent(module, action, { bookingId, detail }, actor));
 save();
}

export function updatePricing(pricing: Pricing, module: 'Pricing' | 'Promotion') {
 requireStaffAction(module === 'Promotion' ? 'changePromotions' : 'changePricing');
 const current = $state.snapshot(db.pricing);
 pricing = module === 'Promotion' ? { ...current, promo: pricing.promo } : { ...pricing, promo: current.promo };
 const amounts = [...Object.values(pricing.ceramic), ...Object.values(pricing.powder), ...Object.values(pricing.size), ...Object.values(pricing.models)];
 if (amounts.some(n => !Number.isFinite(n) || n < 0) || !Number.isFinite(pricing.promo) || pricing.promo < 0 || pricing.promo > 100) throw Error('Use nonnegative amounts and a promotion between 0 and 100%.');
 const catalog = pricing.ceramicCatalog;
 if (catalog) {
  const ranges = Object.values(catalog.addons);
  const rates = [...Object.values(catalog.tiers), ...Object.values(catalog.listedAddons), catalog.premiumGloss];
  if (rates.some(rate => !Number.isFinite(rate) || rate < 0) ||
      ranges.some(([min, max]) => !Number.isFinite(min) || !Number.isFinite(max) || min < 0 || max < min) ||
      catalog.premiumGloss < catalog.listedAddons['Matte to Glossy']) {
   throw Error('Enter nonnegative prices. Maximum and premium prices must be at least the corresponding lower price.');
  }
 }
 const oldPromo = db.pricing.promo;
 const previous = db.pricing.ceramicCatalog ?? defaultCeramicCatalogPricing;
 const tierChanges = catalog ? Object.keys(ceramicTierNames).flatMap(key => {
  const tier = Number(key) as keyof typeof ceramicTierNames;
  return previous.tiers[tier] === catalog.tiers[tier] ? [] :
   [ceramicTierNames[tier] + ': ₱' + previous.tiers[tier] + ' → ₱' + catalog.tiers[tier]];
 }) : [];
 const addonChanges = catalog ? Object.entries(catalog.addons).flatMap(([name, range]) => {
  const old = previous.addons[name as keyof typeof previous.addons];
  return old[0] === range[0] && old[1] === range[1] ? [] : [name + ': ' + old.join('–') + ' → ' + range.join('–')];
 }) : [];
 const listedChanges = catalog ? Object.entries(catalog.listedAddons).flatMap(([name, price]) => {
  const old = previous.listedAddons[name as keyof typeof previous.listedAddons];
  return old === price ? [] : [name + ' (priced tiers): ' + old + ' → ' + price];
 }) : [];
 const premiumChange = catalog && previous.premiumGloss !== catalog.premiumGloss
  ? ['Premium Matte to Glossy: ' + previous.premiumGloss + ' → ' + catalog.premiumGloss] : [];
 db.pricing = pricing;
 audit(module === 'Promotion' ? 'Saved booking promotion' : 'Saved ceramic coating prices', undefined, staffActor(), module,
  module === 'Promotion' ? oldPromo + '% → ' + pricing.promo + '%' :
   [...tierChanges, ...addonChanges, ...listedChanges, ...premiumChange].join(' · ') || 'No rate changes');
}

export function coatingOf(booking: Booking): Selection {
 if (booking.selection) return $state.snapshot(booking.selection);
 const powder = booking.serviceId === 'wheel-colour';
 return { ...selection(powder, booking.finish), ceramicFinish: booking.serviceId === 'ceramic-matte' ? 'Stay Matte' : 'Glossy Finish', powderParts: powder ? ['Wheels / mags'] : [], front: powder ? 'Not sure' : '' };
}

function active(booking: Booking) {
 if (booking.status !== 'pending' && booking.status !== 'confirmed') throw Error('This booking is already closed.');
}

export function editCoating(booking: Booking, input: Selection, actor: 'Customer' | 'Demo admin', adjustments: Record<string, number | undefined> = {}, reason = '') {
 active(booking);
 if (actor === 'Customer' && (booking.status !== 'pending' || booking.requests?.some(r => r.state === 'Pending'))) throw Error('Services can only be edited while the booking is pending and has no request awaiting review.');
 const before = { selection: coatingOf(booking), estimate: $state.snapshot(booking.estimate) };
 if (!booking.bike.trim()) throw Error('Enter the motorcycle model.');
 validateSelection(input, booking.bike, olderPowderParts(before.selection.powderParts));
 if (!before.selection.powder && !booking.walkIn?.immediate) assertServiceDay(input, booking.date);
 const baseEstimate = estimateServiceEdit(booking, input);
 const adjustedLines = actor === 'Demo admin' ? baseEstimate.lines?.filter(line => adjustments[line.label] !== undefined) ?? [] : [];
 if (JSON.stringify(before.selection) === JSON.stringify(input) && !adjustedLines.length) return;
 const estimate = adjustedLines.length ? applyServicePriceAdjustments(baseEstimate, adjustments) : baseEstimate;
 if (actor === 'Demo admin') {
  if (JSON.stringify(before.selection) !== JSON.stringify(input)) requireStaffAction('editServices');
  if (adjustedLines.length) requireStaffAction('adjustPrices');
 }
 const after = { selection: input, estimate };
 const changedBy = actor === 'Customer' ? actor : staffActor();
 booking.serviceChanges = [...(booking.serviceChanges ?? []), { id: crypto.randomUUID(), at: new Date().toISOString(), actor: changedBy, before, after, ...(reason.trim() && { reason: reason.trim() }) }];
 booking.selection = input;
 booking.serviceId = input.ceramic ? 'ceramic' : 'wheel-colour';
 booking.estimate = estimate;
 const priceDetail = adjustedLines.map(line => line.label + ' · ₱' + adjustments[line.label]!.toFixed(2)).join(' · ');
 const detail = [priceDetail, reason.trim() && 'Reason: ' + reason.trim()].filter(Boolean).join(' · ');
 audit('Updated services' + (before.estimate ? ' · ₱' + before.estimate.total + ' → ₱' + estimate.total : ''), booking.id, changedBy, 'Booking', detail || undefined);
}

export function estimateServiceEdit(booking: Booking, input: Selection) {
 return quote(input, booking.size ?? 'small', booking.bike, db.pricing, $state.snapshot(booking.estimate?.lines), booking.modelYear);
}

export function hasUnfinalizedServicePrices(booking: Booking) {
 return booking.estimate?.lines?.some(line => line.pending || line.maximum !== undefined) ?? false;
}

export function requestChange(booking: Booking, kind: ChangeRequest['kind'], reason: string, date?: string, slot?: string) {
 active(booking);
 if (booking.requests?.some(r => r.state === 'Pending')) throw Error('There is already a request awaiting review.');
 if (kind === 'Reschedule') {
  assertServiceDay(booking.selection, date ?? '');
  assertFree(date ?? '', slot ?? '');
 }
 booking.requests = [...(booking.requests ?? []), { kind, reason, date, slot, state: 'Pending', at: new Date().toISOString() }];
 audit(kind + ' requested', booking.id, 'Customer', 'Change requests');
}

export function reviewChange(booking: Booking, request: ChangeRequest, approved: boolean, note = '') {
 requireStaffAction(request.kind === 'Cancel' ? 'reviewCancellation' : 'reviewReschedule');
 active(booking);
 if (request.state !== 'Pending' || !booking.requests?.includes(request)) throw Error('This request has already been reviewed.');
 const previous = booking.date + ' ' + booking.slot;
 const previousStatus = booking.status;
 if (approved && request.kind === 'Reschedule') {
  assertServiceDay(booking.selection, request.date ?? '');
  assertFree(request.date ?? '', request.slot ?? '');
  booking.date = request.date!;
  booking.slot = request.slot!;
  if (booking.walkIn) booking.walkIn.immediate = false;
 }
 if (approved && request.kind === 'Cancel') {
  booking.status = 'cancelled';
  booking.cancelledAt = new Date().toISOString();
  booking.cancellationNote = note.trim();
 }
 request.state = approved ? 'Approved' : 'Declined';
 request.reviewedAt = new Date().toISOString();
 const transition = !approved ? '' : request.kind === 'Reschedule'
  ? ' · ' + previous + ' → ' + booking.date + ' ' + booking.slot
  : ' · ' + previousStatus + ' → cancelled';
 audit(request.kind + ' ' + request.state.toLowerCase() + transition, booking.id, staffActor(), 'Change requests');
 // Production: after either cancellation path commits, email the customer if a note was supplied.
}

export function approveBooking(booking: Booking, note: string) {
 requireStaffAction('confirmBooking');
 if (booking.status !== 'pending') throw Error('Only pending bookings can be confirmed.');
 booking.approvalNote = note;
 setStatus(booking.id, 'confirmed');
}

export function completeBooking(booking: Booking, note: string, photos: string[], finalPrice: number | undefined) {
 requireStaffAction('completeBooking');
 if (booking.status !== 'confirmed') throw Error('Confirm this booking before completing it.');
 if (booking.requests?.some(r => r.state === 'Pending')) throw Error('Review the pending change request before completing this booking.');
 if (hasUnfinalizedServicePrices(booking)) throw Error('Save an exact price for each service that has a range or needs a shop quote.');
 if (!photos.length) throw Error('Attach at least one completion photo.');
 if (photos.length > MAX_COMPLETION_PHOTOS) throw Error('Attach up to ' + MAX_COMPLETION_PHOTOS + ' completion photos.');
 if (photos.some(photo => !photo.startsWith('data:image/jpeg;base64,') || photo.length <= 'data:image/jpeg;base64,'.length)) {
  throw Error('Attach valid completion photos using the camera or album.');
 }
 if (finalPrice === undefined || finalPrice < 0 || !Number.isSafeInteger(Math.round(finalPrice * 100))) throw Error('Enter a valid final service price.');
 const previous = { completionNote: booking.completionNote, photos: booking.photos, completedAt: booking.completedAt, status: booking.status, finalPrice: booking.finalPrice };
 Object.assign(booking, { completionNote: note, photos, completedAt: new Date().toISOString(), status: 'done', finalPrice: Math.round(finalPrice * 100) / 100 });
 try { audit('Confirmed → Done · Added ' + photos.length + (photos.length === 1 ? ' completion photo' : ' completion photos'), booking.id, staffActor(), 'Booking', 'Final service price: ₱' + booking.finalPrice?.toFixed(2)); }
 catch (error) { Object.assign(booking, previous); db.events.pop(); throw error; }
}

export const features = () => proFeatures;


export const bookingsOn = (date: string) =>
	db.bookings.filter((b) => b.date === date && b.status !== 'cancelled' && !b.walkIn?.immediate);

export function isSlotBlocked(date: string, time: string) {
	return db.blockedSlots[date]?.includes(time) ?? false;
}

export function toggleSlotBlock(date: string, time: string) {
	requireStaffAction('manageSchedule');
	if (date < today() || !/^([01]\d|2[0-3]):00$/.test(time)) throw Error('Choose a valid appointment time on today or a future date.');
	const blocked = isSlotBlocked(date, time);
	const previous = db.blockedSlots[date] ?? [];
	db.blockedSlots[date] = blocked ? previous.filter(slot => slot !== time) : [...previous, time];
	audit((blocked ? 'Unblocked ' : 'Blocked ') + date + ' at ' + time, undefined, staffActor(), 'Booking calendar');
}

// The hours of one date: its own choice first, then the open weekdays with the default hours.
export const dateOverride = (date: string) => ({
	closed: db.blocked.includes(date), open: db.opened.includes(date), ownOpen: db.dateHours[date]?.openHour, ownClose: db.dateHours[date]?.closeHour
});
export const dayHours = (date: string) => hoursForDate(db.hours, date, dateOverride(date));

// Any number of customers can share an hour, so a slot is free unless it is blocked or already past.
export function slotsFor(date: string) {
	const past = date === today() ? nowHour() : -1;
	return dayHours(date).hours.map((hour) => {
		const time = String(hour).padStart(2, '0') + ':00';
		return { time, free: !isSlotBlocked(date, time) && hour > past };
	});
}

export const spotsLeft = (date: string) => slotsFor(date).filter((s) => s.free).length;

export function dayStatus(date: string) {
	if (db.blocked.includes(date)) return 'blocked';
	if (dayHours(date).closed) return 'closed';
	return spotsLeft(date) > 0 ? 'open' : 'full';
}

// The real build checks the date's hours and blocks inside the database save, not in the browser.
function assertFree(date: string, slot: string) {
	if (!isBookableDate(date) || dayStatus(date) !== 'open' || !slotsFor(date).find((s) => s.time === slot)?.free)
		throw new Error('That time is no longer available. Please pick another.');
}

function assertServiceDay(selection: Selection | undefined, date: string) {
	if (selection?.catalog && selection.powder && !powderDay(date))
		throw Error('Choose a Wednesday, Saturday, or Sunday for powder coating.');
}

export function book(input: NewBooking) {
	if (input.bookedByStaff || input.walkIn?.immediate) requireStaffAction('createBooking');
	if (!input.walkIn?.immediate) assertServiceDay(input.selection, input.date);
	if (!input.walkIn?.immediate) assertFree(input.date, input.slot);
	if (input.selection) validateSelection(input.selection, input.bike);
	const estimate = input.selection ? quote(input.selection, input.size ?? 'small', input.bike, db.pricing, [], input.modelYear) : undefined;
	const originalServices = input.selection ? { selection: structuredClone(input.selection), estimate: structuredClone(estimate) } : undefined;
	const booking: Booking = { ...input, estimate, originalServices, id: code(), status: 'pending', createdAt: new Date().toISOString() };
	db.bookings.push(booking);
	audit(input.walkIn ? 'Recorded walk-in intake' : 'Booking submitted · Pending', booking.id, input.bookedByStaff ? staffActor() : 'Customer');
	return booking;
}

export function reschedule(id: string, date: string, slot: string) {
	requireStaffAction('rescheduleBooking');
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

export function setStatus(id: string, status: 'confirmed' | 'cancelled', note = '') {
	requireStaffAction(status === 'confirmed' ? 'confirmBooking' : 'cancelBooking');
	const booking = db.bookings.find(b => b.id === id)!;
	active(booking);
	if (status === 'cancelled' && booking.requests?.some(r => r.state === 'Pending')) throw Error('Review the pending change request first.');
	const previous = booking.status;
	booking.status = status;
	if (status === 'confirmed') booking.approvedAt = new Date().toISOString();
	if (status === 'cancelled') {
		booking.cancelledAt = new Date().toISOString();
		booking.cancellationNote = note.trim();
		// Production: enqueue a cancellation email with the customer-visible note after saving.
	}
	audit(previous + ' → ' + status, id);
}

export function setDateAvailability(date: string, override: 'open' | 'closed' | 'regular') {
 requireStaffAction('manageSchedule');
 if (date < today()) throw Error('Choose today or a future date.');
 db.blocked = db.blocked.filter(day => day !== date);
 db.opened = db.opened.filter(day => day !== date);
 delete db.dateHours[date];
 if (override === 'closed') db.blocked.push(date);
 if (override === 'open') db.opened.push(date);
 const action = { open: 'Opened bookings', closed: 'Closed bookings', regular: 'Restored regular hours' };
 audit(action[override] + ' for ' + date, undefined, staffActor(), 'Booking calendar');
}
