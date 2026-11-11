<script lang="ts">
 import BookingSummary from './BookingSummary.svelte';
 import EditCoating from './EditCoating.svelte';
 import { fmtDate, fmtSlot } from './dates';
 import { approveBooking, completeBooking, reviewChange, setStatus, type Booking } from './store.svelte';
 let { booking }: { booking: Booking } = $props();
 let approval = $state('');
 let note = $state('');
 let photos = $state<string[]>([]);
 let completing = $state(false);
 let reading = $state(false);
 let error = $state('');
 const active = $derived(booking.status === 'confirmed' || booking.status === 'pending');
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
 <BookingSummary {booking} staff />
 {#each booking.requests ?? [] as request}
  <div class="card stack">
   <p><strong>{request.kind} request</strong> <span class="badge" data-status={request.state.toLowerCase()}>{request.state}</span></p>
   {#if request.date && request.slot}<p>Requested visit: {fmtDate(request.date)} at {fmtSlot(request.slot)}</p>{/if}
   {#if request.reason}<p>Reason: {request.reason}</p>{/if}
   {#if request.state === 'Pending' && active}
    <div class="row"><button class="btn sm confirm-action" onclick={() => run(() => reviewChange(booking, request, true))}>Approve {request.kind.toLowerCase()}</button><button class="btn sm danger" onclick={() => run(() => reviewChange(booking, request, false))}>Decline request</button></div>
   {/if}
  </div>
 {/each}
 {#if active}<EditCoating {booking} staff />{/if}
 {#if booking.status === 'pending'}
  <form class="stack" onsubmit={(event) => { event.preventDefault(); run(() => approveBooking(booking, approval.trim())); }}>
   <label>Approval note for the customer (optional)<textarea rows="2" maxlength="1000" bind:value={approval}></textarea></label>
   <div><button class="btn sm confirm-action">Confirm booking</button></div>
  </form>
 {:else if booking.status === 'confirmed'}
  {#if completing}
   <form class="card stack" onsubmit={(event) => { event.preventDefault(); run(() => { completeBooking(booking, note.trim(), [...photos]); completing = false; }); }}>
    <label>Completion details (optional)<textarea rows="2" maxlength="1000" bind:value={note}></textarea></label>
    <div class="cols"><label>Take a photo<input type="file" accept="image/*" capture="environment" onchange={addPhoto} disabled={reading || photos.length >= 3} /></label>
    <label>Upload a photo<input type="file" accept="image/jpeg,image/png,image/webp,image/avif" onchange={addPhoto} disabled={reading || photos.length >= 3} /></label></div>
    {#if reading}<p role="status">Preparing photo…</p>{/if}
    {#if photos.length}<div class="cols">{#each photos as photo, index}<div class="stack"><img src={photo} alt={'Photo ' + (index + 1)} /><button type="button" class="btn sm ghost" onclick={() => photos = photos.filter((_, i) => i !== index)}>Remove photo {index + 1}</button></div>{/each}</div>{/if}
    <div class="row"><button class="btn sm complete-action" disabled={reading}>Mark as done</button><button type="button" class="btn sm ghost" onclick={() => completing = false}>Close</button></div>
   </form>
  {:else}
   <div><button class="btn sm complete-action" onclick={() => completing = true}>Complete service</button></div>
  {/if}
 {/if}
 {#if active && !booking.requests?.some(r => r.state === 'Pending')}
  <div><button class="btn sm danger" onclick={() => { if (confirm('Cancel this booking?')) run(() => setStatus(booking.id, 'cancelled')); }}>Cancel booking</button></div>
 {/if}
 {#if error}<p class="error" role="alert">{error}</p>{/if}
</div>
<style>img { max-height: 160px; object-fit: contain; }</style>
