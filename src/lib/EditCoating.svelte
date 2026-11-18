<script lang="ts">
 import ActionIcon from '#lib/ActionIcon.svelte';
 import CoatingFields from './CoatingFields.svelte';
 import BookingCatalog from './BookingCatalog.svelte';
 import { applyServicePriceAdjustments, estimatePrice, linePrice, olderPowderParts, selection, serviceLabel } from './coating';
 import { coatingOf, editCoating, estimateServiceEdit, type Booking } from './store.svelte';
 import { canPerform } from './staffAccess.svelte.ts';
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
 const canEdit = $derived(!staff || canPerform('editServices'));
 const canAdjust = $derived(staff && canPerform('adjustPrices'));

 function openEditor() {
  value = coatingOf(booking);
  initialSelection = JSON.stringify(value);
  error = '';
  adjustments = {};
  dialog.showModal();
 }

 function save(event: SubmitEvent) {
  event.preventDefault();
  try {
   if (staff) editCoating(booking, $state.snapshot(value), 'Demo admin', $state.snapshot(adjustments));
   else if (changed) editCoating(booking, $state.snapshot(value), 'Customer');
   dialog.close();
  } catch (e) { error = (e as Error).message; }
 }
</script>
<button type="button" class="btn sm ghost" onclick={openEditor}><ActionIcon name="edit" />{canEdit ? 'Edit services' : 'Adjust service prices'}</button>
<dialog bind:this={dialog} aria-label="Edit booking services">
 <form class="stack" onsubmit={save}>
  <h3>{canEdit ? 'Edit services' : 'Adjust service prices'}</h3>
  {#if original}<div class="card"><strong>Original booking</strong><p>{serviceLabel(original.selection)}</p>{#each original.estimate?.lines ?? [] as line}<p>{line.label} · {linePrice(line)}</p>{/each}{#if original.estimate}<p>{estimatePrice(original.estimate)}</p>{/if}</div>{/if}
  <div class="card"><strong>Before this edit</strong><p>{serviceLabel(coatingOf(booking))}</p><p>{booking.estimate ? estimatePrice(booking.estimate) : 'No saved price'}</p></div>
  {#if canEdit}
   {#if value.catalog}
    <BookingCatalog bind:value bike={booking.bike} year={booking.modelYear} {olderParts} />
   {:else}
    <CoatingFields bind:value bike={booking.bike} />
   {/if}
  {/if}
  <section class="stack" aria-label="Service cart">
  <h4>Service cart</h4>
  {#each estimate.lines ?? [] as line (line.label)}
   <div class="card"><strong>{line.label}</strong><p>Price {linePrice(line)}</p>
    {#if canAdjust}<label>Adjusted price for {line.label} (₱)<input type="number" min="0" step="0.01" bind:value={adjustments[line.label]} placeholder="Keep current price" /></label>{/if}
   </div>
  {/each}
  <p>Updated estimate <strong>{estimatePrice(canAdjust ? preview : estimate)}</strong></p>
  </section>
  {#if booking.estimate && !booking.estimate.lines}<p class="small muted">This older booking has no saved prices per service. Saving a change uses current prices and keeps the previous estimate in history.</p>{/if}
  {#if error}<p class="error" role="alert">{error}</p>{/if}
  <div class="row"><button class="btn sm"><ActionIcon name="save" />{canEdit ? 'Save services' : 'Save prices'}</button><button type="button" class="btn sm ghost" onclick={() => dialog.close()}><ActionIcon name="close" />Close</button></div>
 </form>
</dialog>
<style>
 dialog { width: min(900px, calc(100% - 24px)); max-height: 90dvh; padding: 1rem; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); }
 dialog::backdrop { background: #0009; }
</style>
