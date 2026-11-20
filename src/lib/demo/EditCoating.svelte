<script lang="ts">
 import ActionIcon from '#lib/shared/ActionIcon.svelte';
 import CoatingFields from './CoatingFields.svelte';
 import BookingCatalog from './BookingCatalog.svelte';
 import { applyServicePriceAdjustments, estimatePrice, linePrice, money, olderPowderParts, selection, serviceLabel } from '../shared/coating';
 import { coatingOf, editCoating, estimateServiceEdit, type Booking } from './store.svelte';
 import { canPerform } from './staffAccess.svelte.ts';
 let { booking, staff = false }: { booking: Booking; staff?: boolean } = $props();
 let dialog: HTMLDialogElement;
 let adjustments = $state<Record<string, string | undefined>>({});
 let value = $state(selection());
 let error = $state('');
 let initialSelection = $state('');
 const olderParts = $derived(olderPowderParts(coatingOf(booking).powderParts));
 const changed = $derived(JSON.stringify(value) !== initialSelection);
 const estimate = $derived((!changed && booking.estimate?.lines && booking.estimate) || estimateServiceEdit(booking, value));
 const pricePattern = '([0-9]+([.,][0-9]{0,2})?|[.,][0-9]{1,2})';
 const validPrice = new RegExp('^' + pricePattern + '$');
 const pricedLines = $derived((estimate.lines ?? []).flatMap(line => {
  const text = adjustments[line.label]?.trim();
  if (!text) return [];
  const price = Number(text.replace(',', '.'));
  return [{ label: line.label, price: validPrice.test(text) && Number.isSafeInteger(Math.round(price * 100)) ? price : undefined }];
 }));
 const numericAdjustments = $derived(Object.fromEntries(pricedLines.filter(line => line.price !== undefined).map(({ label, price }) => [label, price])));
 const preview = $derived(applyServicePriceAdjustments(estimate, numericAdjustments));
 const original = $derived(booking.originalServices);
 const existingLines = $derived(new Set(booking.estimate?.lines?.map(line => line.label)));
 const titleId = $props.id();
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
  error = '';
  try {
   if (staff) {
    if (canAdjust && pricedLines.some(line => line.price === undefined)) throw Error('Enter a valid nonnegative amount with up to two decimal places.');
    editCoating(booking, $state.snapshot(value), 'Demo admin', canAdjust ? numericAdjustments : {});
   }
   else if (changed) editCoating(booking, $state.snapshot(value), 'Customer');
   dialog.close();
  } catch (e) { error = (e as Error).message; }
 }
</script>
<button type="button" class="btn sm ghost" onclick={openEditor}><ActionIcon name="edit" />{canEdit ? 'Edit services' : 'Adjust service prices'}</button>
<dialog bind:this={dialog} aria-labelledby={titleId}>
 <form onsubmit={save}>
  <header class="editor-header">
   <div><h3 id={titleId}>{canEdit ? 'Edit services' : 'Adjust service prices'}</h3><p class="muted small">{booking.bike} · {booking.id}</p></div>
   <button type="button" class="btn sm ghost close" onclick={() => dialog.close()}>Close</button>
  </header>
  <div class="editor-body stack">
   <div class="booking-baseline">
    <div><span class="muted small">Current booking</span><strong>{serviceLabel(coatingOf(booking))}</strong></div>
    <span class="current-total">{booking.estimate ? estimatePrice(booking.estimate) : 'No saved price'}</span>
   </div>
   {#if original}
    <details class="original">
     <summary>Original booking {#if original.estimate}<strong>{estimatePrice(original.estimate)}</strong>{/if}</summary>
     <div class="original-body">
      {#if original.estimate?.lines?.length}
       <dl>
        {#each original.estimate.lines as line (line.label)}
         <div><dt>{line.label}</dt><dd>{linePrice(line)}</dd></div>
        {/each}
       </dl>
      {:else}
       <p>{serviceLabel(original.selection)}</p>
      {/if}
     </div>
    </details>
   {/if}
   <section class="stack" aria-label="Service cart">
    <div><h4>Service cart</h4>{#if canAdjust}<p class="small muted">Leave an adjusted price blank to keep the listed price.</p>{/if}</div>
    {#if estimate.lines?.length}
     <ul class="service-list">
      {#each estimate.lines as line (line.label)}
       {@const [name, ...details] = line.label.split(' · ')}
       <li class:adjustable={canAdjust}>
        <div class="line-name"><strong>{name}</strong>{#if details.length}<span class="small muted">{details.join(' · ')}</span>{/if}</div>
        <div class="line-price">
         <span class="small muted">{existingLines.has(line.label) ? 'Current price' : 'Catalog price'}</span>
         <strong>{linePrice(line)}</strong>
         {#if line.discount}<span class="small muted">{money(line.discount)} discount</span>{/if}
        </div>
        {#if canAdjust}
         <label class="adjustment">
          <span class="small muted">Adjusted price</span>
          <span class="price-input"><span aria-hidden="true">₱</span><input aria-label={'Adjusted price for ' + line.label + ' (₱)'} type="text" inputmode="decimal" pattern={pricePattern} title="Enter a nonnegative amount with up to two decimal places." bind:value={adjustments[line.label]} placeholder={line.pending || line.maximum !== undefined ? 'Enter amount' : line.subtotal.toFixed(2)} /></span>
         </label>
        {/if}
       </li>
      {/each}
     </ul>
    {:else}
     <p class="small muted">Select a service to see its price.</p>
    {/if}
    {#if booking.estimate && !booking.estimate.lines}<p class="small muted">This booking predates itemized prices. The original estimate stays in the booking history.</p>{/if}
   </section>
   {#if canEdit}
    <section class="stack" aria-label="Service options">
     <h4>Service options</h4>
     {#if value.catalog}
      <BookingCatalog bind:value bike={booking.bike} year={booking.modelYear} {olderParts} />
     {:else}
      <CoatingFields bind:value bike={booking.bike} />
     {/if}
    </section>
   {/if}
  </div>
  <footer class="editor-footer">
   {#if error}<p class="error" role="alert">{error}</p>{/if}
   <div class="row footer-row">
    <div class="updated-total" aria-live="polite"><span class="muted small">Updated estimate</span><strong>{estimatePrice(canAdjust ? preview : estimate)}</strong></div>
    <button class="btn sm"><ActionIcon name="save" />{canEdit ? 'Save services' : 'Save prices'}</button>
   </div>
  </footer>
 </form>
</dialog>
<style>
 dialog { width: min(780px, calc(100% - 24px)); max-height: 90dvh; padding: 0; border: 1px solid var(--line); border-radius: 14px; background: var(--panel); color: var(--text); }
 dialog::backdrop { background: #0009; }
 form { display: grid; grid-template-rows: auto minmax(0, 1fr) auto; max-height: calc(90dvh - 2px); }
 .editor-header, .editor-footer { padding: .9rem clamp(.8rem, 3vw, 1.4rem); }
 .editor-header { display: flex; align-items: flex-start; justify-content: space-between; gap: .75rem; border-bottom: 1px solid var(--line); }
 .editor-header h3 { margin-bottom: .2rem; }
 .close { padding-inline: .7rem; clip-path: none; border-radius: 6px; font-style: normal; }
 .editor-body { overflow-y: auto; padding: 1rem clamp(.8rem, 3vw, 1.4rem); }
 .booking-baseline { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: .4rem 1rem; padding: .8rem; border-radius: 8px; background: var(--panel-2); }
 .booking-baseline > div, .updated-total, .line-name, .line-price { display: grid; gap: .15rem; min-width: 0; }
 .current-total, .line-price strong, .updated-total strong, .original dd { font-variant-numeric: tabular-nums; }
 .current-total { font-weight: 700; }
 .original { border: 1px solid var(--line); border-radius: 8px; }
 .original summary { cursor: pointer; padding: .65rem .8rem; font-weight: 600; }
 .original summary strong { float: inline-end; margin-inline-start: .65rem; }
 .original-body { padding: 0 .8rem .7rem; }
 .original dl, .original dd { margin: 0; }
 .original dl > div { display: flex; justify-content: space-between; gap: .5rem; padding: .3rem 0; }
 .original dd { text-align: end; }
 .service-list { margin: 0; padding: 0; list-style: none; border: 1px solid var(--line); border-radius: 8px; }
 .service-list li { display: grid; grid-template-columns: minmax(0, 1fr) minmax(5.5rem, auto); align-items: center; gap: .5rem 1rem; padding: .75rem .8rem; }
 .service-list li.adjustable { grid-template-columns: minmax(0, 1fr) minmax(5.5rem, auto) minmax(7rem, 9.5rem); }
 .service-list li + li { border-top: 1px solid var(--line); }
 .line-name, .line-price { overflow-wrap: anywhere; }
 .adjustment { gap: .22rem; }
 .price-input { display: flex; align-items: center; gap: .1rem; padding-inline-start: .6rem; border: 1px solid var(--line); border-radius: 6px; background: var(--bg); color: var(--muted); }
 .price-input:focus-within { outline: 2px solid var(--accent); outline-offset: 1px; }
 .price-input input { min-width: 0; border: 0; box-shadow: none; background: transparent; padding: .45rem .4rem; font-variant-numeric: tabular-nums; }
 .price-input input:focus-visible { outline: none; }
 .editor-footer { border-top: 1px solid var(--line); background: var(--panel-2); }
 .footer-row { justify-content: space-between; gap: .5rem 1rem; }
 .updated-total strong { color: var(--accent); }
 @media (max-width: 490px) {
  .service-list li.adjustable { grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); }
  .service-list li.adjustable .line-name { grid-column: 1 / -1; }
 }
</style>
