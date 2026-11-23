<script lang="ts">
	// The one booking-details popup used by every demo staff list.
	import DetailsSheet from '../shared/DetailsSheet.svelte';
	import DemoBookingDetails from './DemoBookingDetails.svelte';
	import type { Booking } from './store.svelte';

	let { booking = $bindable() }: { booking?: Booking } = $props();
</script>

<DetailsSheet title={booking ? 'Details for ' + (booking.name || 'booking') : 'Booking details'} open={Boolean(booking)} onclose={() => booking = undefined}>{#if booking}<DemoBookingDetails {booking} />{/if}</DetailsSheet>
