<script lang="ts">
	// Everything about one booking, shown inside the shared details sheet (demo).
	import { sizes } from '../shared/config';
	import BookingSummary from './BookingSummary.svelte';
	import type { Booking } from './store.svelte';

	let { booking }: { booking: Booking } = $props();
</script>

<div class="stack">
	<p class="small muted">{booking.id} · {booking.walkIn ? 'Walk-in' : 'Online'}</p>
	<BookingSummary {booking} staff />
	<section class="stack">
		<h4>Customer and motorcycle</h4>
		<p>{[booking.bike || 'Not provided', booking.plateNumber && 'Plate ' + booking.plateNumber, booking.size && sizes[booking.size], booking.finish && 'Finish: ' + booking.finish].filter(Boolean).join(' · ')}</p>
		<p>{booking.name || 'Not provided'} · {#if booking.phone}<a href={'tel:' + booking.phone}>{booking.phone}</a>{:else}No mobile{/if}</p>
		{#if booking.email}<p><a href={'mailto:' + booking.email}>{booking.email}</a></p>{/if}
	</section>
	<section class="stack"><h4>Notes for the shop</h4><p class="notes">{booking.notes || 'No notes provided.'}</p></section>
</div>

<style>
	h4, p { margin: 0; }
	h4 { font-size: 1rem; }
	.notes { white-space: pre-wrap; }
</style>
