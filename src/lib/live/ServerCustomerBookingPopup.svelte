<!-- Styles load together with this popup (not in the My bookings first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// The customer's booking details: the shared Reports popup (customer variant) with services and inclusions,
	// totals (the original struck through when the shop changed it), the change log, and their own change requests.
	// Loaded only when a card is opened. Staff names, reasons, notes and contact rows are never shown here.
	import ReportDetails, { type Detail } from '../shared/ReportDetails.svelte';
	import { fmtDate, fmtSlot } from '../shared/dates';
	import { bookingWasUpdated } from '../shared/booking-changes';
	import BookingServiceEditor from './BookingServiceEditor.svelte';
	import CoatingOptionSummary from './CoatingOptionSummary.svelte';
	import CustomerChangeLog from './CustomerChangeLog.svelte';
	import ServerBookingActivity from './ServerBookingActivity.svelte';
	import ServerSharedBookingDetails from './ServerSharedBookingDetails.svelte';
	import { displayEstimate, displayServicePrice } from './service-estimate';
	import type { CustomerBooking, CustomerChangeRequest } from './server-booking-types';
	import type { CoatingOptions } from './booking-coating';

	let { booking, requests, onclose }: { booking: CustomerBooking; requests: CustomerChangeRequest[]; onclose: () => void } = $props();
	const price = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
	const stamp = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' });
	const services = $derived(booking.current_services ?? booking.original_services);
	const updated = $derived(bookingWasUpdated({ originalTotal: booking.original_total_centavos, currentTotal: booking.current_total_centavos,
		originalCodes: booking.original_services.map((service) => service.code), currentCodes: booking.current_services?.map((service) => service.code) }));
	const detail = $derived<Detail>({
		name: '', ref: booking.reference_no ? 'HG-' + booking.reference_no : booking.id, status: booking.status, walkIn: booking.visit_hour === null,
		lines: services.map((service) => ({
			label: service.label, price: displayServicePrice(service),
			parts: service.promotion ? [{ label: service.promotion.label + ', regular ' + price.format(service.promotion.base_price_centavos / 100) }] : undefined
		})),
		total: displayEstimate(services, booking.current_total_centavos ?? booking.original_total_centavos),
		originalTotal: updated ? displayEstimate(booking.original_services, booking.original_total_centavos) : undefined,
		bike: booking.bike,
		visit: fmtDate(booking.visit_date) + ' · ' + (booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00')),
		booked: stamp.format(new Date(booking.created_at)),
		approved: booking.approved_at ? stamp.format(new Date(booking.approved_at)) : 'Awaiting approval',
		completed: booking.completed_at ? stamp.format(new Date(booking.completed_at)) : 'Not completed'
	});
</script>

<ReportDetails {detail} variant="customer" {onclose} changes={changeLog} inclusions={coating} actions={more} />

{#snippet coating()}<CoatingOptionSummary options={booking.coating_options as CoatingOptions | undefined} />{/snippet}
{#snippet changeLog()}
	{#if updated}<p class="updated small">Updated by the shop after inspection</p>{/if}
	<CustomerChangeLog bookingId={booking.id} />
{/snippet}
{#snippet more()}
	<BookingServiceEditor bookingId={booking.id} fromStaff={false} shopPriced={booking.shop_priced && (booking.status === 'pending' || booking.status === 'confirmed')} embedded />
	<ServerSharedBookingDetails bookingId={booking.id} />
	<ServerBookingActivity bookingId={booking.id} />
	{#if requests.length}
		<section class="requests" aria-label="Change requests">
			<h4>Change requests</h4>
			<ul>
				{#each requests as request (request.id)}
					<li>{request.kind === 'cancel' ? 'Cancellation' : 'Rescheduling'} · {request.state}{#if request.target_date && request.target_hour !== null} · {fmtDate(request.target_date)} at {fmtSlot(request.target_hour + ':00')}{/if}
						{#if request.reason}<p class="small">{request.reason}</p>{/if}</li>
				{/each}
			</ul>
		</section>
	{/if}
{/snippet}

<style>
	.updated { margin: 0; padding: .4rem .6rem; border: 1px solid var(--info-line); border-radius: 8px; background: var(--panel-2); font-weight: 650; }
	.requests { display: grid; gap: .4rem; padding: .85rem; border: 1px solid var(--line); border-radius: 12px; }
	h4 { margin: 0; font-size: .75rem; letter-spacing: .05em; text-transform: uppercase; }
	ul { display: grid; gap: .35rem; margin: 0; padding: 0; list-style: none; }
	p { margin: 0; }
</style>
