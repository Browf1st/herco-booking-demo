<script lang="ts">
 import ActionIcon from '#lib/ActionIcon.svelte';
 import BookingSummary from './BookingSummary.svelte';
 import VisitPicker from './VisitPicker.svelte';
 import EditCoating from './EditCoating.svelte';
 import { fmtDate, fmtSlot } from './dates';
 import { canPerform } from './staffAccess.svelte.ts';
 import { approveBooking, completeBooking, reschedule, reviewChange, setStatus, type Booking, type ChangeRequest } from './store.svelte';
 let { booking, summary = true }: { booking: Booking; summary?: boolean } = $props();
 let moveDialog = $state<HTMLDialogElement>();
 let moveDate = $state('');
 let moveSlot = $state('');
 let moveError = $state('');
 let cancelDialog = $state<HTMLDialogElement>();
 let cancelNote = $state('');
 let cancelError = $state('');
 let cancellationRequest = $state.raw<ChangeRequest>();
 let approval = $state('');
 let note = $state('');
 let photos = $state<string[]>([]);
 let completing = $state(false);
 let finalPrice = $state<number>();
 let reading = $state(false);
 let error = $state('');
 const active = $derived(booking.status === 'confirmed' || booking.status === 'pending');
 const pending = $derived(booking.requests?.some(r => r.state === 'Pending'));
 function openCancellation(request?: ChangeRequest) {
  cancellationRequest = request;
  cancelNote = cancelError = '';
  cancelDialog?.showModal();
 }
 function cancel(event: SubmitEvent) {
  event.preventDefault();
  try {
   if (cancellationRequest) reviewChange(booking, cancellationRequest, true, cancelNote);
   else setStatus(booking.id, 'cancelled', cancelNote);
   cancelDialog?.close();
  }
  catch (e) { cancelError = (e as Error).message; }
 }
 function run(action: () => void) {
  error = '';
  try { action(); } catch (e) { error = (e as Error).message; }
 }
 async function addPhoto(event: Event) {
  const field = event.currentTarget as HTMLInputElement;
  const file = field.files?.[0];
  field.value = '';
  if (!file || reading) return;
  if (!['image/jpeg','image/png','image/webp','image/avif'].includes(file.type) || file.size > 15 * 1024 * 1024 || photos.length >= 3) {
   error = 'Use a JPEG, PNG, WebP or AVIF image up to 15 MB. You can attach up to three photos.';
   return;
  }
  reading = true;
  error = '';
  try {
   const image = await createImageBitmap(file);
   try {
    const ratio = Math.min(1, 800 / Math.max(image.width, image.height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(image.width * ratio));
    canvas.height = Math.max(1, Math.round(image.height * ratio));
    canvas.getContext('2d')!.drawImage(image, 0, 0, canvas.width, canvas.height);
    photos = [...photos, canvas.toDataURL('image/jpeg', 0.74)];
   } finally { image.close(); }
  } catch { error = 'Could not read this image. Try a different photo.'; }
  finally { reading = false; }
 }
</script>
<div class="stack">
 {#if summary}<BookingSummary {booking} staff />{/if}
 {#each (booking.requests ?? []).filter(request => request.state === 'Pending') as request}
  <div class="card stack">
   <p><strong>{request.kind} request</strong> <span class="badge" data-status={request.state.toLowerCase()}>{request.state}</span></p>
   {#if request.date && request.slot}<p>Requested visit: {fmtDate(request.date)} at {fmtSlot(request.slot)}</p>{/if}
   {#if request.reason}<p>Reason: {request.reason}</p>{/if}
   {#if active && canPerform(request.kind === 'Cancel' ? 'reviewCancellation' : 'reviewReschedule')}
    <div class="row"><button class="btn sm confirm-action" onclick={() => request.kind === 'Cancel' ? openCancellation(request) : run(() => reviewChange(booking, request, true))}><ActionIcon name="check" />{request.kind === 'Cancel' ? 'Approve cancellation' : 'Approve reschedule'}</button><button class="btn sm danger" onclick={() => run(() => reviewChange(booking, request, false))}><ActionIcon name="close" />Decline request</button></div>
   {/if}
  </div>
 {/each}
 {#if active && (canPerform('editServices') || canPerform('adjustPrices'))}<div><EditCoating {booking} staff /></div>{/if}
 {#if booking.status === 'pending' && !pending && canPerform('confirmBooking')}
  <form class="stack" onsubmit={(event) => { event.preventDefault(); run(() => approveBooking(booking, approval.trim())); }}>
   <label>Approval note for the customer (optional)<textarea rows="2" maxlength="1000" bind:value={approval}></textarea></label>
   <div><button class="btn sm confirm-action"><ActionIcon name="check" />Confirm booking</button></div>
  </form>
 {:else if booking.status === 'confirmed' && !pending && canPerform('completeBooking')}
  {#if completing}
   <form class="card stack" onsubmit={(event) => { event.preventDefault(); run(() => { completeBooking(booking, note.trim(), [...photos], finalPrice); completing = false; }); }}>
    <label>Final service price (₱)<input type="number" min="0" step="0.01" required bind:value={finalPrice} /></label>
    <p class="muted small">Enter the final amount charged after any service changes or discounts.</p>
    <label>Completion details (optional)<textarea rows="2" maxlength="1000" bind:value={note}></textarea></label>
    <div class="cols"><label>Take a photo<input type="file" accept="image/*" capture="environment" onchange={addPhoto} disabled={reading || photos.length >= 3} /></label>
    <label>Upload a photo<input type="file" accept="image/jpeg,image/png,image/webp,image/avif" onchange={addPhoto} disabled={reading || photos.length >= 3} /></label></div>
    {#if reading}<p role="status">Preparing photo…</p>{/if}
    {#if photos.length}<div class="cols">{#each photos as photo, index}<div class="stack"><img src={photo} alt={'Photo ' + (index + 1)} /><button type="button" class="btn sm ghost" onclick={() => photos = photos.filter((_, i) => i !== index)}><ActionIcon name="close" />Remove photo {index + 1}</button></div>{/each}</div>{/if}
    <div class="row"><button class="btn sm complete-action" disabled={reading}><ActionIcon name="check" />Mark as done</button><button type="button" class="btn sm ghost" onclick={() => completing = false}><ActionIcon name="close" />Close</button></div>
   </form>
  {:else}
   <div><button class="btn sm complete-action" onclick={() => completing = true}><ActionIcon name="check" />Complete service</button></div>
  {/if}
 {/if}
 {#if active && !pending && (canPerform('rescheduleBooking') || canPerform('cancelBooking'))}
  <div class="row">
   {#if canPerform('rescheduleBooking')}<button type="button" class="btn sm ghost" onclick={() => { moveDate = moveSlot = moveError = ''; moveDialog?.showModal(); }}><ActionIcon name="calendar" />Reschedule booking</button>{/if}
   {#if canPerform('cancelBooking')}<button class="btn sm danger" onclick={() => openCancellation()}><ActionIcon name="block" />Cancel booking</button>{/if}
  </div>
 {/if}
 {#if error}<p class="error" role="alert">{error}</p>{/if}
</div>
{#if canPerform('rescheduleBooking')}
<dialog bind:this={moveDialog} aria-label="Reschedule booking">
 <form class="stack" onsubmit={(event) => { event.preventDefault(); try { reschedule(booking.id, moveDate, moveSlot); moveDialog?.close(); } catch (e) { moveError = (e as Error).message; } }}>
  <h3>Reschedule booking</h3>
  <VisitPicker bind:date={moveDate} bind:slot={moveSlot} powder={!!(booking.selection?.catalog && booking.selection.powder)} />
  {#if moveError}<p class="error" role="alert">{moveError}</p>{/if}
  <div class="row"><button type="button" class="btn sm ghost" onclick={() => moveDialog?.close()}>Keep current visit</button><button class="btn sm" disabled={!moveDate || !moveSlot}>Save new visit</button></div>
 </form>
</dialog>
{/if}
{#if canPerform('cancelBooking') || canPerform('reviewCancellation')}
<dialog bind:this={cancelDialog} aria-label="Cancel booking">
 <form class="stack" onsubmit={cancel}>
  <h3>{cancellationRequest ? 'Approve cancellation' : 'Cancel booking'}</h3>
  <p>Cancel {booking.id} for {booking.name}? The appointment time will be released.</p>
  <label>Note for the customer (optional)<textarea rows="3" maxlength="1000" bind:value={cancelNote}></textarea></label>
  {#if cancelError}<p class="error" role="alert">{cancelError}</p>{/if}
  <div class="row"><button type="button" class="btn sm ghost" onclick={() => cancelDialog?.close()}>Go back</button><button class="btn sm danger">{cancellationRequest ? 'Approve cancellation' : 'Cancel booking'}</button></div>
 </form>
</dialog>
{/if}
<style>dialog { width: min(520px, calc(100% - 24px)); max-height: 90dvh; padding: 1rem; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); } dialog::backdrop { background: #0009; } img { max-height: 160px; object-fit: contain; }</style>
