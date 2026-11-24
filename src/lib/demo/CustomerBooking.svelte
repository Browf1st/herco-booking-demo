<script lang="ts">
 import ActionIcon from '#lib/shared/ActionIcon.svelte';
 import { tick } from 'svelte';
 import VisitPicker from './VisitPicker.svelte';
 import BookingSummary from './BookingSummary.svelte';
 import { fmtDate, fmtSlot } from '../shared/dates';
 import { serviceOf } from '../shared/config';
 import { estimatePrice, serviceLabel } from '../shared/coating';
 import { bookingWasUpdated } from '../shared/booking-changes';
 import { bookingStatusLabels, requestChange, type Booking, type ChangeRequest } from './store.svelte';
 let { booking }: { booking: Booking } = $props();
 let kind = $state<ChangeRequest['kind']>();
 let date = $state('');
 let slot = $state('');
 let reason = $state('');
 let error = $state('');
 let dialog: HTMLDialogElement;
 const active = $derived(['pending', 'confirmed'].includes(booking.status));
 const pending = $derived(booking.requests?.some(r => r.state === 'Pending'));
 // The shop changed a price or the services after booking: show the old total struck through.
 const original = $derived(booking.originalServices?.estimate);
 const updated = $derived(Boolean(original) && bookingWasUpdated({ originalTotal: original?.total, currentTotal: booking.estimate?.total, originalCodes: original?.lines?.map(line => line.label) ?? [], currentCodes: booking.estimate?.lines?.map(line => line.label) }));
 // Once staff changed a line price, the customer can no longer edit services (same rule as the live app).
 const shopPriced = $derived((booking.serviceChanges ?? []).some(change => change.actor !== 'Customer' && (change.after.estimate?.lines ?? []).some(line => {
  const old = change.before.estimate?.lines?.find(item => item.label === line.label);
  return old !== undefined && old.subtotal !== line.subtotal;
 })));
 async function openRequest(value: ChangeRequest['kind']) {
  kind = value;
  date = slot = reason = error = '';
  await tick();
  dialog.showModal();
 }
 function submit(event: SubmitEvent) {
  event.preventDefault();
  if (!kind) return;
  try {
   requestChange(booking, kind, reason.trim(), kind === 'Reschedule' ? date : undefined, kind === 'Reschedule' ? slot : undefined);
   dialog.close();
   kind = undefined;
   date = slot = reason = error = '';
  } catch (e) { error = (e as Error).message; }
 }
</script>
<article class="card stack">
 <header class="row booking-header">
  <div class="row"><h2>{booking.id}</h2><span class="badge" data-status={booking.status === 'confirmed' ? 'booked' : booking.status}>{bookingStatusLabels[booking.status]}</span></div>
  {#if active && !pending}
   <div class="row"><button class="btn sm ghost" onclick={() => openRequest('Reschedule')}><ActionIcon name="calendar" />Request reschedule</button><button class="btn sm danger" onclick={() => openRequest('Cancel')}><ActionIcon name="block" />Request cancellation</button></div>
  {/if}
 </header>
 <p><ActionIcon name="box" /> <strong>{booking.selection ? serviceLabel(booking.selection) : serviceOf(booking.serviceId).name}</strong> · {booking.bike}</p>
 <div class="row">
  <p><ActionIcon name="calendar" /> <strong>Visit</strong> · {fmtDate(booking.date)} at {fmtSlot(booking.slot)}</p>
  {#if booking.estimate}<p>Estimated service value {#if updated && original}<s><span class="sr-only">Original total </span>{estimatePrice(original)}</s> {/if}<strong>{estimatePrice(booking.estimate)}</strong></p>{/if}
 </div>
 {#if updated}<p class="small updated-note">Updated by the shop after inspection</p>{/if}
 {#if active && pending}
  <p class="small muted">Your original visit stays reserved while the shop reviews your request.</p>
 {/if}
 <details>
  <summary>View details</summary>
  <div class="stack booking-details">
   <BookingSummary {booking} overviewShown />
   {#each booking.requests ?? [] as request}
    <p>{request.kind}{request.date && request.slot ? ' · ' + fmtDate(request.date) + ' at ' + fmtSlot(request.slot) : ''} <span class="badge" data-status={request.state.toLowerCase()}>{request.state === 'Pending' ? 'Awaiting shop approval' : request.state}</span></p>
    {#if request.reason}<p class="small muted">Your note: {request.reason}</p>{/if}
   {/each}
   {#if booking.status === 'pending' && shopPriced}<p class="small muted" role="status">The shop updated this booking after inspection. Contact the shop to change services.</p>
   {:else if booking.status === 'pending' && !pending}{#await import('./EditCoating.svelte') then { default: EditCoating }}<EditCoating {booking} />{/await}{/if}
  </div>
 </details>
 <dialog bind:this={dialog} aria-label="Request a booking change">
  {#if kind}
   <form class="card stack" onsubmit={submit}>
    <h3>{kind === 'Cancel' ? 'Request cancellation' : 'Request rescheduling'}</h3>
    <p class="small muted">Your current visit stays reserved until the shop approves your request.</p>
    {#if kind === 'Reschedule'}<VisitPicker bind:date bind:slot powder={!!(booking.selection?.catalog && booking.selection.powder)} />{/if}
    <label>Reason (optional)<textarea bind:value={reason} maxlength="500" rows="2"></textarea></label>
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    <div class="row"><button class="btn sm" disabled={kind === 'Reschedule' && (!date || !slot)}><ActionIcon name="send" />Send request</button><button type="button" class="btn sm ghost" onclick={() => dialog.close()}><ActionIcon name="back" />Back</button></div>
   </form>
  {/if}
 </dialog>
</article>
<style>
 h2 { font-size: 1.8rem; }
 .booking-header { justify-content: space-between; }
 .booking-details { margin-top: .75rem; }
 .updated-note { margin: 0; padding: 6px 10px; border: 1px solid var(--info-line); border-radius: 8px; background: var(--panel-2); color: var(--text); font-weight: 650; }
 .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
 dialog { width: min(570px, calc(100% - 24px)); max-height: 90dvh; padding: 0; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); }
 dialog::backdrop { background: #0009; }
</style>
