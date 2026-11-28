<script lang="ts">
 import { page } from '$app/state';
 import ServerBooking from '#lib/live/ServerBooking.svelte';
 // /book?edit=<booking id> opens the full booking form prefilled to edit that pending booking.
 const edit = $derived(page.url.searchParams.get('edit') ?? '');
 const editId = $derived(/^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i.test(edit) ? edit : '');
</script>

{#key editId}
 <ServerBooking editBookingId={editId} />
{/key}
