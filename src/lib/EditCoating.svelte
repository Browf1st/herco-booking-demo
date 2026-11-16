<script lang="ts">
 import ActionIcon from '#lib/ActionIcon.svelte';
 import CoatingFields from './CoatingFields.svelte';
 import BookingCatalog from './BookingCatalog.svelte';
 import { estimatePrice, olderPowderParts, selection } from './coating';
 import { coatingOf, editCoating, estimateServiceEdit, type Booking } from './store.svelte';
 let { booking }: { booking: Booking } = $props();
 let editing = $state(false);
 let value = $state(selection());
 let error = $state('');
 let initialSelection = $state('');
 const olderParts = $derived(olderPowderParts(coatingOf(booking).powderParts));
 const changed = $derived(JSON.stringify(value) !== initialSelection);
 const estimate = $derived((!changed && booking.estimate) || estimateServiceEdit(booking, value));

 function openEditor() {
  value = coatingOf(booking);
  initialSelection = JSON.stringify(value);
  error = '';
  editing = true;
 }

 function save(event: SubmitEvent) {
  event.preventDefault();
  try {
   if (changed) editCoating(booking, $state.snapshot(value), 'Customer');
   editing = false;
  } catch (e) { error = (e as Error).message; }
 }
</script>
{#if editing}
 <form class="stack card" onsubmit={save}>
  {#if value.catalog}
   <BookingCatalog bind:value bike={booking.bike} year={booking.modelYear} {olderParts} />
  {:else}
   <CoatingFields bind:value bike={booking.bike} />
  {/if}
  <p>Updated estimate <strong>{estimatePrice(estimate)}</strong></p>
  {#if booking.estimate && !booking.estimate.lines}<p class="small muted">This older booking has no saved prices per service. Saving a change uses current prices and keeps the previous estimate in history.</p>{/if}
  {#if error}<p class="error" role="alert">{error}</p>{/if}
  <div class="row"><button class="btn sm"><ActionIcon name="save" />Save services</button><button type="button" class="btn sm ghost" onclick={() => editing = false}><ActionIcon name="close" />Close</button></div>
 </form>
{:else}
 <div><button type="button" class="btn sm ghost" onclick={openEditor}><ActionIcon name="edit" />Edit services</button></div>
{/if}
