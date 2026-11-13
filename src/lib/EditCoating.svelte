<script lang="ts">
 import CoatingFields from './CoatingFields.svelte';
 import BookingCatalog from './BookingCatalog.svelte';
 import { estimatePrice, selection } from './coating';
 import { coatingOf, editCoating, estimateServiceEdit, type Booking } from './store.svelte';
 let { booking, staff = false }: { booking: Booking; staff?: boolean } = $props();
 let editing = $state(false);
 let value = $state(selection());
 let error = $state('');
 const estimate = $derived(estimateServiceEdit(booking, value));
 function save(event: SubmitEvent) {
  event.preventDefault();
  try {
   editCoating(booking, $state.snapshot(value), staff ? 'Demo admin' : 'Customer');
   editing = false;
  } catch (e) { error = (e as Error).message; }
 }
</script>
{#if editing}
 <form class="stack card" onsubmit={save}>
  {#if value.catalog}
   <BookingCatalog bind:value bike={booking.bike} year={booking.modelYear} />
  {:else}
   <CoatingFields bind:value bike={booking.bike} />
  {/if}
  <p>Updated estimate <strong>{estimatePrice(estimate)}</strong></p>
  {#if booking.estimate && !booking.estimate.lines}<p class="small muted">This older booking has no saved prices per service. Saving a change uses current prices and keeps the previous estimate in history.</p>{/if}
  {#if error}<p class="error" role="alert">{error}</p>{/if}
  <div class="row"><button class="btn sm">Save services</button><button type="button" class="btn sm ghost" onclick={() => editing = false}>Close</button></div>
 </form>
{:else}
 <div><button type="button" class="btn sm ghost" onclick={() => { value = coatingOf(booking); error = ''; editing = true; }}>Edit services</button></div>
{/if}
