<script lang="ts">
	import { page } from '$app/state';
	import BookingServiceEditor from '#lib/live/BookingServiceEditor.svelte';
	const bookingId = $derived(page.url.searchParams.get('booking') ?? '');
	const fromStaff = $derived(page.url.searchParams.get('from') === 'staff');
</script>

{#if import.meta.env.MODE === 'worker'}
	{#key bookingId}
		<BookingServiceEditor {bookingId} {fromStaff} />
	{/key}
{:else}
	<section class="section wrap stack"><h1>Booking services</h1><p>Open a booking in the demo to view its services.</p></section>
{/if}
