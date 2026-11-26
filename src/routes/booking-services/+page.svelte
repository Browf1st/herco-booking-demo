<script lang="ts">
	import { page } from '$app/state';
	import BookingServiceEditor from '#lib/live/BookingServiceEditor.svelte';
	const bookingId = $derived(page.url.searchParams.get('booking') ?? '');
	const fromStaff = $derived(page.url.searchParams.get('from') === 'staff');
</script>

	{#key bookingId}
		<BookingServiceEditor {bookingId} {fromStaff} />
	{/key}
