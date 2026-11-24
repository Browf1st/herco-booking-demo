<script lang="ts">
 import type { Snippet } from 'svelte';
 import { canPerform } from './staffAccess.svelte.ts';
 import ActionIcon from '../shared/ActionIcon.svelte';
 import { fmtDate, fmtSlot } from '../shared/dates';
 import { serviceOf } from '../shared/config';
 import { defaultPricing, estimatePrice, linePrice, money, quote, serviceLabel, type Selection } from '../shared/coating';
 import { db, type Booking } from './store.svelte';
 // linesEditor (optional) replaces the plain price list with one staff can edit.
 let { booking, staff = false, overviewShown = false, linesEditor }: { booking: Booking; staff?: boolean; overviewShown?: boolean; linesEditor?: Snippet } = $props();
 const events = $derived(db.events.filter(e => e.bookingId === booking.id && (staff || e.actor === 'Customer' || !e.action.startsWith('Recorded walk-in'))));
 const stamp = (at?: string) => at ? new Date(at).toLocaleString('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short', hour12: true }) : 'Not recorded';
 const labels = (selection: Selection, estimate?: ReturnType<typeof quote>) =>
  (estimate?.lines ?? quote(selection, booking.size ?? 'small', booking.bike, defaultPricing, [], booking.modelYear).lines ?? []).map(line => line.label);
</script>

{#if !overviewShown}
 <p><ActionIcon name="box" /> <strong>{booking.selection ? serviceLabel(booking.selection) : serviceOf(booking.serviceId).name}</strong> · {booking.bike}{booking.modelYear ? ' · Model year ' + booking.modelYear : ''}</p>
{:else if booking.modelYear}
 <p>Model year {booking.modelYear}</p>
{/if}
<div class="cols" aria-label="Booking dates in Philippine time">
 {#if !overviewShown}<p><ActionIcon name="calendar" /> <strong>Visit</strong><br />{fmtDate(booking.date)} · {fmtSlot(booking.slot)}</p>{/if}
 <p><ActionIcon name="clock" /> <strong>Booked on</strong><br />{stamp(booking.createdAt ?? booking.walkIn?.at)}</p>
 <p><ActionIcon name="check" /> <strong>Approved</strong><br />{booking.status === 'pending' ? 'Awaiting approval' : stamp(booking.approvedAt)}</p>
 <p><ActionIcon name="finish" /> <strong>Completed</strong><br />{booking.status === 'done' ? stamp(booking.completedAt) : 'Not completed'}</p>
</div>
{#if booking.selection?.ceramic && !booking.selection.catalog}<p>Ceramic finish: {booking.selection.ceramicFinish}</p>{/if}
{#if booking.selection?.powder}
 <p>Powder coating: {booking.selection.powderParts.join(', ')}{booking.selection.finish ? ' · ' + booking.selection.finish : ''}</p>
 {#if !booking.selection.catalog && booking.selection.powderParts.includes('Wheels / mags')}<p>Mag diameter · Front: {booking.selection.front || '—'} · Rear: {booking.selection.rear || '—'} (inches)</p>{/if}
{/if}
{#if booking.estimate}
 {#if !overviewShown}<p>{staff ? 'Price' : 'Estimated service value'} <strong>{estimatePrice(booking.estimate)}</strong>{#if booking.estimate.discount} · {money(booking.estimate.discount)} promo discount{/if}</p>
 {:else if booking.estimate.discount}<p>Promo discount <strong>{money(booking.estimate.discount)}</strong></p>{/if}
{/if}
{#if booking.estimate?.lines?.length}
 {#if linesEditor}{@render linesEditor()}{:else}
 <ul aria-label="Current service prices">{#each booking.estimate.lines as line (line.label)}<li>{line.label} · {linePrice(line)}</li>{/each}</ul>
 {/if}
{/if}
{#if booking.originalServices || booking.serviceChanges?.length}
 <section class="card stack" aria-label="Service history">
  <h3>Service history</h3>
  {#if booking.originalServices}
   <div>
    <strong>Original booking</strong>
    <ul>{#each labels(booking.originalServices.selection, booking.originalServices.estimate) as label}<li>{label}{#each (booking.originalServices.estimate?.lines ?? []).filter(line => line.label === label) as line} · {linePrice(line)}{/each}</li>{/each}</ul>
    {#if booking.originalServices.estimate}<p>Original estimate <strong>{estimatePrice(booking.originalServices.estimate)}</strong></p>{/if}
   </div>
  {:else}
   <p class="small muted">Original booking details are unavailable for this older record. History starts with the first recorded edit.</p>
  {/if}
  {#each booking.serviceChanges ?? [] as change (change.id)}
   {@const before = labels(change.before.selection, change.before.estimate)}
   {@const after = labels(change.after.selection, change.after.estimate)}
   <div class="service-change">
    <strong>Changed after booking</strong>
    <p class="small muted">{staff || change.actor === 'Customer' ? change.actor : 'Shop staff'} · {stamp(change.at)} PH time</p>
    <ul>
     {#each after.filter(label => !before.includes(label)) as label}<li><strong>Added</strong> {label}</li>{/each}
     {#each before.filter(label => !after.includes(label)) as label}<li><strong>Removed</strong> {label}</li>{/each}
    </ul>
    {#each change.after.estimate?.lines ?? [] as line}
     {@const old = change.before.estimate?.lines?.find(item => item.label === line.label)}
     <p>{line.label} · {old && linePrice(old) !== linePrice(line) ? linePrice(old) + ' → ' : ''}{linePrice(line)}</p>
    {/each}
    {#if change.after.estimate}<p>Estimate {change.before.estimate ? estimatePrice(change.before.estimate) + ' → ' : ''}<strong>{estimatePrice(change.after.estimate)}</strong></p>{/if}
   </div>
  {/each}
 </section>
{/if}
{#if staff && booking.requests?.length}
 <section class="stack" aria-label="Change request history">
  <h3>Change requests</h3>
  {#each booking.requests as request}
   <div><strong>{request.kind} · {request.state}</strong><p class="small muted">Requested {stamp(request.at)}{request.reviewedAt ? ' · Reviewed ' + stamp(request.reviewedAt) : ''}</p>
   {#if request.date && request.slot}<p>Requested visit: {fmtDate(request.date)} · {fmtSlot(request.slot)}</p>{/if}
   {#if request.reason}<p>Customer note: {request.reason}</p>{/if}</div>
  {/each}
 </section>
{/if}
{#if booking.approvalNote}<p>Note from the shop: {booking.approvalNote}</p>{/if}
{#if booking.cancelledAt}<p>Cancelled · {stamp(booking.cancelledAt)}</p>{/if}
{#if booking.cancellationNote}<p>Cancellation note: {booking.cancellationNote}</p>{/if}
{#if booking.completionNote}<p>Completion notes: {booking.completionNote}</p>{/if}
{#if booking.photos?.length}
 <div class="cols">{#each booking.photos as photo, i}<img src={photo} alt={'Completion photo ' + (i + 1)} loading="lazy" />{/each}</div>
{/if}
{#if staff && booking.walkIn}<p>Walk-in intake · {booking.walkIn.version} · Signed by {booking.walkIn.signer} on {new Date(booking.walkIn.at).toLocaleString('en-PH', {timeZone:'Asia/Manila', hour12:true})}</p>{/if}
{#if events.length}
 <details><summary>Activity · Philippine time</summary>
  <ul>{#each events as event (event.id)}<li>{stamp(event.at)} · {event.action} · {staff || event.actor === 'Customer' ? event.actor : 'Shop staff'}{#if staff && event.detail && (!event.detail.startsWith('Final service price:') || canPerform('viewIncome'))} · {event.detail}{/if}</li>{/each}</ul>
 </details>
{/if}
<style>
 img { width: 100%; max-height: 220px; object-fit: contain; background: var(--panel-2); border-radius: 6px; }
 ul { margin-block: 4px; padding-inline-start: 22px; }
 .service-change { padding-top: 12px; border-top: 1px solid var(--line); }
</style>
