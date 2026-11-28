import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { prefillBike, prefillSelection } from '../src/lib/live/booking-prefill.ts';
import { menuItems } from '../src/lib/live/booking-menu.ts';

const read = (path) => readFile(new URL('../' + path, import.meta.url), 'utf8');

test('a listed model selects its tier radio', () => {
	assert.deepEqual(prefillBike('Yamaha NMAX', true, {}), { unit: 'Yamaha NMAX', custom: '', powderBike: '' });
	assert.deepEqual(prefillBike('Honda PCX160', true, {}), { unit: 'Honda PCX160', custom: '', powderBike: '' });
});

test('a model that is not listed uses the "not listed" path with the text kept', () => {
	assert.deepEqual(prefillBike('Yamaha MT-15', true, {}), { unit: 'other', custom: 'Yamaha MT-15', powderBike: '' });
});

test('a booking saved as another big bike reopens on the big bike path', () => {
	const options = { ui_catalog: { other_big_bike: true, big_bike: true } };
	assert.deepEqual(prefillBike('Ducati Monster', true, options), { unit: 'other-big-bike', custom: 'Ducati Monster', powderBike: '' });
});

test('powder-only bookings keep the bike in the powder motorcycle box', () => {
	assert.deepEqual(prefillBike('Yamaha Sniper 155', false, {}), { unit: '', custom: '', powderBike: 'Yamaha Sniper 155' });
	assert.deepEqual(prefillBike('', false, undefined), { unit: '', custom: '', powderBike: '' });
});

test('saved services, add-ons, parts and finish fill the selection', () => {
	const options = { powder_parts: ['Wheels / mags'], ui_catalog: { ceramic_addons: ['Inner coating'], finish: 'Matte Black', wheel_extras: ['x'], big_bike: true } };
	const value = prefillSelection(options, ['ceramic', 'wheel-colour'], {});
	assert.equal(value.ceramic, true);
	assert.equal(value.powder, true);
	assert.deepEqual(value.powderParts, ['Wheels / mags']);
	assert.equal(value.finish, 'Matte Black');
	assert.deepEqual(value.catalog.ceramicAddons, ['Inner coating']);
	assert.equal(value.catalog.bigBike, true);
	const none = prefillSelection(undefined, ['ceramic'], {});
	assert.equal(none.powder, false);
	assert.deepEqual(none.powderParts, []);
});

test('only pending, future, unpriced bookings get Edit service', () => {
	const base = { visitHour: 9, future: true, requestsReady: true, hasOpenRequest: false };
	assert.ok(menuItems({ ...base, status: 'pending' }).includes('edit-service'));
	assert.ok(menuItems({ ...base, status: 'confirmed' }).includes('view-service'));
	assert.ok(menuItems({ ...base, status: 'pending', shopPriced: true }).includes('view-service'));
});

test('the booking screen has an edit mode that saves through /api/bookings/edit and hides the date step', async () => {
	const screen = await read('src/lib/live/ServerBooking.svelte');
	assert.match(screen, /editBookingId/);
	assert.match(screen, /\/api\/booking-services'\) \+ '\?' \+ new URLSearchParams\(\{ booking: editBookingId \}\)/);
	assert.match(screen, /resolve\('\/api\/bookings\/edit'\)/);
	assert.match(screen, /To change the date, use Reschedule from My bookings\./);
	assert.match(screen, /'Save changes'/);
	assert.match(screen, /\{#if !manualGuest&&!editMode\}<label class="booking-source">/);
	assert.match(screen, /code: 'shop_priced'|failure\?\.code !== 'shop_priced'/);
	const page = await read('src/routes/book/+page.svelte');
	assert.match(page, /searchParams\.get\('edit'\)/);
});

test('My bookings sends Edit service to the full edit screen and gates the shop-updated note on shop_priced', async () => {
	const history = await read('src/lib/live/ServerBookingHistory.svelte');
	assert.match(history, /item === 'edit-service'\) void goto\(resolve\('\/book'\) \+ '\?edit='/);
	assert.match(history, /\{#if updated && booking\.shop_priced\}/);
	assert.match(history, /readOnly embedded/);
	const popup = await read('src/lib/live/ServerCustomerBookingPopup.svelte');
	assert.match(popup, /\{#if updated && booking\.shop_priced\}/);
});
