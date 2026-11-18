<script lang="ts">
 import ActionIcon from '#lib/ActionIcon.svelte';
 import type { Snippet } from 'svelte';
 import VisitPicker from './VisitPicker.svelte';
 import EditCoating from './EditCoating.svelte';
 import { fmtDate, fmtSlot } from './dates';
 import { canPerform } from './staffAccess.svelte.ts';
 import { approveBooking, completeBooking, hasUnfinalizedServicePrices, MAX_COMPLETION_PHOTOS, reschedule, reviewChange, setStatus, type Booking, type ChangeRequest } from './store.svelte';
 let { booking, heading, children }: { booking: Booking; heading: Snippet; children?: Snippet } = $props();
 let moveDialog = $state<HTMLDialogElement>();
 let moveDate = $state('');
 let moveSlot = $state('');
 let moveError = $state('');
 let cancelDialog = $state<HTMLDialogElement>();
 let cancelNote = $state('');
 let cancelError = $state('');
 let cancellationRequest = $state.raw<ChangeRequest>();
 let approvalDialog = $state<HTMLDialogElement>();
 let reviewDialog = $state<HTMLDialogElement>();
 let more = $state<HTMLDetailsElement>();
 let approval = $state('');
 let note = $state('');
 let photos = $state<string[]>([]);
 let completing = $state(false);
 let finalPrice = $state<number>();
 let reading = $state(false);
 let cameraInput = $state<HTMLInputElement>();
 let albumInput = $state<HTMLInputElement>();
 const acceptedPhotos = ['image/jpeg', 'image/png', 'image/webp', 'image/avif'];
 let error = $state('');
 const active = $derived(booking.status === 'confirmed' || booking.status === 'pending');
 const pending = $derived(booking.requests?.find(request => request.state === 'Pending'));
 const canReview = $derived(active && pending && canPerform(pending.kind === 'Cancel' ? 'reviewCancellation' : 'reviewReschedule'));
 const canEdit = $derived(active && (canPerform('editServices') || canPerform('adjustPrices')));
 const canMove = $derived(active && !pending && canPerform('rescheduleBooking'));
 const canCancel = $derived(active && !pending && canPerform('cancelBooking'));
 const needsPrices = $derived(hasUnfinalizedServicePrices(booking));
 const showPriceWarning = $derived(booking.status === 'confirmed' && !pending && needsPrices && canPerform('completeBooking'));
 const priceWarningId = $props.id();
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
   reviewDialog?.close();
  }
  catch (e) { cancelError = (e as Error).message; }
 }
 function run(action: () => void) {
  error = '';
  try { action(); } catch (e) { error = (e as Error).message; }
 }
 async function addPhotos(event: Event) {
  const field = event.currentTarget as HTMLInputElement;
  const files = Array.from(field.files ?? []);
  field.value = '';
  if (!files.length || reading) return;
  reading = true;
  error = '';
  const problems = new Set<string>();
  try {
   for (const file of files) {
    if (photos.length >= MAX_COMPLETION_PHOTOS) {
     problems.add('Only ' + MAX_COMPLETION_PHOTOS + ' photos can be attached.');
     break;
    }
    if (!acceptedPhotos.includes(file.type) || file.size > 15 * 1024 * 1024) {
     problems.add('Use JPEG, PNG, WebP or AVIF files up to 15 MB each.');
     continue;
    }
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
    } catch { problems.add('Could not read one of the images. Try a different photo.'); }
   }
  } finally {
   error = [...problems].join(' ');
   reading = false;
  }
 }
</script>
<div class="booking-header">
 <div class="booking-heading">{@render heading()}</div>
 {#if active && !completing && (pending || canEdit || canMove || canCancel || canPerform('confirmBooking') || canPerform('completeBooking'))}
  <div class="row booking-actions">
   {#if pending}
    {#if canReview}
     <button type="button" class="btn sm" onclick={() => { error = ''; reviewDialog?.showModal(); }}><ActionIcon name="check" />Review {pending.kind === 'Cancel' ? 'cancellation' : 'reschedule'}</button>
    {:else}
     <span class="badge" data-status="pending">{pending.kind === 'Cancel' ? 'Cancellation' : 'Reschedule'} requested</span>
    {/if}
   {:else if booking.status === 'pending' && canPerform('confirmBooking')}
    <button type="button" class="btn sm confirm-action" onclick={() => { approval = error = ''; approvalDialog?.showModal(); }}><ActionIcon name="check" />Confirm booking</button>
   {:else if booking.status === 'confirmed' && canPerform('completeBooking')}
    <button type="button" class="btn sm complete-action" disabled={needsPrices} aria-describedby={showPriceWarning ? priceWarningId : undefined} onclick={() => { error = ''; completing = true; }}><ActionIcon name="check" />Complete service</button>
   {/if}
   {#if canEdit || canMove || canCancel}
    <details class="more" bind:this={more}>
     <summary class="btn sm ghost">More actions <span aria-hidden="true">▾</span></summary>
     <div class="more-options">
      {#if canEdit}<EditCoating {booking} staff />{/if}
      {#if canMove}<button type="button" class="btn sm ghost" onclick={() => { if (more) more.open = false; moveDate = moveSlot = moveError = ''; moveDialog?.showModal(); }}><ActionIcon name="calendar" />Reschedule booking</button>{/if}
      {#if canCancel}<button type="button" class="btn sm danger" onclick={() => { if (more) more.open = false; openCancellation(); }}><ActionIcon name="block" />Cancel booking</button>{/if}
     </div>
    </details>
   {/if}
  </div>
 {/if}
</div>
 {#if showPriceWarning}
  <p id={priceWarningId} class="price-warning small" role="status">
   {canPerform('adjustPrices') ? 'Set an exact price for every range or shop quote under More actions before completing this booking.' : 'Ask someone with price adjustment access to finalize the service prices before completing this booking.'}
  </p>
 {/if}
 {@render children?.()}
 {#if booking.status === 'confirmed' && !pending && canPerform('completeBooking') && completing}
   <form class="card stack" onsubmit={(event) => { event.preventDefault(); run(() => { completeBooking(booking, note.trim(), [...photos], finalPrice); completing = false; }); }}>
    <label>Final service price (₱)<input type="number" min="0" step="0.01" required bind:value={finalPrice} /></label>
    <p class="muted small">Enter the final amount charged after any service changes or discounts.</p>
    <label>Completion details (optional)<textarea rows="2" maxlength="1000" bind:value={note}></textarea></label>
    <p class="muted small">Attach at least one completion photo. You can add up to {MAX_COMPLETION_PHOTOS}.</p>
    <div class="row">
     <input type="file" hidden aria-label="Camera photo" bind:this={cameraInput} accept="image/*" capture="environment" onchange={addPhotos} />
     <input type="file" hidden aria-label="Album photos" bind:this={albumInput} accept={acceptedPhotos.join(',')} multiple onchange={addPhotos} />
     <button type="button" class="btn sm ghost" onclick={() => cameraInput?.click()} disabled={reading || photos.length >= MAX_COMPLETION_PHOTOS}><ActionIcon name="add" />Take a photo</button>
     <button type="button" class="btn sm ghost" onclick={() => albumInput?.click()} disabled={reading || photos.length >= MAX_COMPLETION_PHOTOS}><ActionIcon name="add" />Upload from album</button>
    </div>
    <p class="small muted" role="status">{reading ? 'Preparing photos…' : photos.length + ' of ' + MAX_COMPLETION_PHOTOS + ' attached'}</p>
    {#if photos.length}<div class="cols">{#each photos as photo, index}<div class="stack"><img src={photo} alt={'Photo ' + (index + 1)} /><button type="button" class="btn sm ghost" disabled={reading} onclick={() => { photos = photos.filter((_, i) => i !== index); error = ''; }}><ActionIcon name="close" />Remove photo {index + 1}</button></div>{/each}</div>{/if}
    <div class="row"><button class="btn sm complete-action" disabled={reading || !photos.length || needsPrices}><ActionIcon name="check" />Mark as done</button><button type="button" class="btn sm ghost" onclick={() => completing = false}><ActionIcon name="close" />Close</button></div>
   </form>
 {/if}
 {#if error}<p class="error" role="alert">{error}</p>{/if}
{#if booking.status === 'pending' && !pending && canPerform('confirmBooking')}
 <dialog bind:this={approvalDialog} aria-label="Confirm booking">
  <form class="stack" onsubmit={(event) => { event.preventDefault(); run(() => { approveBooking(booking, approval.trim()); approvalDialog?.close(); }); }}>
   <h3>Confirm booking</h3>
   <label>Approval note for the customer (optional)<textarea rows="2" maxlength="1000" bind:value={approval}></textarea></label>
   {#if error}<p class="error" role="alert">{error}</p>{/if}
   <div class="row"><button class="btn sm confirm-action">Confirm booking</button><button type="button" class="btn sm ghost" onclick={() => approvalDialog?.close()}>Go back</button></div>
  </form>
 </dialog>
{/if}
{#if pending && canReview}
 {@const request = pending}
 <dialog bind:this={reviewDialog} aria-label="Review booking request">
  <div class="stack">
   <h3>{request.kind === 'Cancel' ? 'Cancellation request' : 'Reschedule request'}</h3>
   {#if request.date && request.slot}<p>Requested visit: {fmtDate(request.date)} at {fmtSlot(request.slot)}</p>{/if}
   {#if request.reason}<p>Reason: {request.reason}</p>{/if}
   {#if error}<p class="error" role="alert">{error}</p>{/if}
   <div class="row">
    <button class="btn sm confirm-action" onclick={() => request.kind === 'Cancel' ? openCancellation(request) : run(() => { reviewChange(booking, request, true); reviewDialog?.close(); })}>{request.kind === 'Cancel' ? 'Approve cancellation' : 'Approve reschedule'}</button>
    <button class="btn sm danger" onclick={() => run(() => { reviewChange(booking, request, false); reviewDialog?.close(); })}>Decline request</button>
    <button class="btn sm ghost" onclick={() => reviewDialog?.close()}>Go back</button>
   </div>
  </div>
 </dialog>
{/if}
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
<style>dialog { width: min(520px, calc(100% - 24px)); max-height: 90dvh; padding: 1rem; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); } dialog::backdrop { background: #0009; } img { max-height: 160px; object-fit: contain; }
 .booking-header { display: flex; flex-wrap: wrap; gap: .55rem 1rem; align-items: flex-start; }
 .booking-heading { flex: 1 1 14rem; min-width: 0; }
 .booking-actions { flex: none; max-width: 100%; gap: .4rem; }
 .price-warning { margin-block-start: .5rem; color: var(--warn); }
 .more { position: relative; }
 .more summary { list-style: none; cursor: pointer; }
 .more summary::-webkit-details-marker { display: none; }
 .more-options { position: absolute; z-index: 2; inset: calc(100% + .25rem) 0 auto auto; width: max-content; max-width: min(15rem, calc(100vw - 3rem)); display: grid; gap: .25rem; padding: .35rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); box-shadow: 0 4px 12px var(--card-shadow); }
 .more-options :global(.btn) { justify-content: flex-start; width: 100%; border-radius: 4px; clip-path: none; font-style: normal; }
 @media (max-width: 520px) {
  .more-options { position: static; margin-top: .25rem; }
  .booking-header { flex-direction: column; }
  .booking-heading { flex: none; max-width: 100%; }
  .booking-actions { align-items: flex-start; }
 }
</style>
