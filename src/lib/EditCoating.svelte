<script lang="ts">
 import ActionIcon from '#lib/ActionIcon.svelte';
 import CoatingFields from './CoatingFields.svelte';
 import BookingCatalog from './BookingCatalog.svelte';
 import { applyServicePriceAdjustments, estimatePrice, linePrice, olderPowderParts, selection } from './coating';
 import { catalogSelectionOf, coatingOf, editCoating, estimateServiceEdit, type Booking } from './store.svelte';
 let { booking, staff = false }: { booking: Booking; staff?: boolean } = $props();
 let dialog: HTMLDialogElement;
 let adjustments = $state<Record<string, number | undefined>>({});
 let value = $state(selection());
 let error = $state('');
 let initialSelection = $state('');
 const olderParts = $derived(olderPowderParts(coatingOf(booking).powderParts));
 const changed = $derived(JSON.stringify(value) !== initialSelection);
 const estimate = $derived((!changed && booking.estimate) || estimateServiceEdit(booking, value));
 const preview = $derived(applyServicePriceAdjustments(estimate, Object.fromEntries(Object.entries(adjustments).filter(([, price]) => price !== undefined && price >= 0 && Number.isSafeInteger(Math.round(price * 100))))));
 const original = $derived(booking.originalServices ?? booking.serviceChanges?.[0]?.before);

 function openEditor() {
  value = staff ? catalogSelectionOf(booking) : coatingOf(booking);
  initialSelection = JSON.stringify(value);
  error = '';
  adjustments = {};
  dialog.showModal();
 }

 function save(event: SubmitEvent) {
  event.preventDefault();
  try {
   if (staff) editCoating(booking, $state.snapshot(value), 'Demo admin', { bike: booking.bike, size: booking.size, modelYear: booking.modelYear, notes: booking.notes, adjustments: $state.snapshot(adjustments) });
   else if (changed) editCoating(booking, $state.snapshot(value), 'Customer');
   dialog.close();
  } catch (e) { error = (e as Error).message; }
 }
</script>
<button type="button" class="btn sm ghost" onclick={openEditor}><ActionIcon name="edit" />Edit services</button>
<dialog bind:this={dialog} aria-label="Edit booking services">
 <form class="stack" onsubmit={save}>
  <h3>Edit services</h3>
  {#if original}<div class="card"><strong>Original booking</strong>{#each original.estimate?.lines ?? [] as line}<p>{line.label} · {linePrice(line)}</p>{/each}{#if original.estimate}<p>{estimatePrice(original.estimate)}</p>{/if}</div>{/if}
  {#if value.catalog}
   <BookingCatalog bind:value bike={booking.bike} year={booking.modelYear} {olderParts} />
  {:else}
   <CoatingFields bind:value bike={booking.bike} />
  {/if}
  {#each estimate.lines ?? [] as line}
   <div class="card"><strong>{line.label}</strong><p>Price {linePrice(line)}</p>
    {#if staff}<label>Adjusted price (₱)<input type="number" min="0" step="0.01" bind:value={adjustments[line.label]} placeholder="Keep current price" /></label>{/if}
   </div>
  {/each}
  <p>Updated estimate <strong>{estimatePrice(staff ? preview : estimate)}</strong></p>
  {#if booking.estimate && !booking.estimate.lines}<p class="small muted">This older booking has no saved prices per service. Saving a change uses current prices and keeps the previous estimate in history.</p>{/if}
  {#if error}<p class="error" role="alert">{error}</p>{/if}
  <div class="row"><button class="btn sm"><ActionIcon name="save" />Save services</button><button type="button" class="btn sm ghost" onclick={() => dialog.close()}><ActionIcon name="close" />Close</button></div>
 </form>
</dialog>
<style>
 dialog { width: min(900px, calc(100% - 24px)); max-height: 90dvh; padding: 1rem; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); }
 dialog::backdrop { background: #0009; }
</style>
