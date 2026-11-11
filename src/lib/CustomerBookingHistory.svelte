<script lang="ts">
 import { account, browserBookingIds } from './account.svelte';
 import { db, sampleServiceBookingId } from './store.svelte';
 import CustomerBooking from './CustomerBooking.svelte';

 const guestIds = typeof localStorage === 'undefined' ? [] : browserBookingIds();
 const bookings = $derived(db.bookings.filter(booking =>
  booking.accountId ? booking.accountId === account.current?.id : guestIds.includes(booking.id)
 ).toReversed());
 const sample = $derived(db.bookings.find(booking => booking.id === sampleServiceBookingId));
</script>

{#if account.current}
 {#each bookings as booking (booking.id)}
  <CustomerBooking {booking} />
 {:else}
  {#if sample}
   <p class="small muted">No bookings yet. Here’s a sample showing a service added after booking.</p>
   <CustomerBooking booking={sample} />
  {:else}
   <p class="card">No bookings for this demo account or browser yet.</p>
  {/if}
 {/each}
{:else}
 <p class="card">Sign in to view your booking history.</p>
{/if}
