<script lang="ts">
 import { serviceOf } from './config';
 import { defaultPricing, money, quote, serviceLabel, type Selection } from './coating';
 import { db, type Booking } from './store.svelte';
 let { booking, staff = false }: { booking: Booking; staff?: boolean } = $props();
 const events = $derived(db.events.filter(e => e.bookingId === booking.id && (staff || e.actor === 'Customer' || !e.action.startsWith('Recorded walk-in'))));
 const labels = (selection: Selection) => quote(selection, booking.size ?? 'small', booking.bike, defaultPricing).lines?.map(line => line.label) ?? [];
</script>

<p><strong>{booking.selection ? serviceLabel(booking.selection) : serviceOf(booking.serviceId).name}</strong> · {booking.bike}{booking.modelYear ? ' · Model year ' + booking.modelYear : ''}</p>
{#if booking.selection?.ceramic}<p>Ceramic finish: {booking.selection.ceramicFinish}</p>{/if}
{#if booking.selection?.powder}
 <p>Powder coating: {booking.selection.powderParts.join(', ')}{booking.selection.finish ? ' · ' + booking.selection.finish : ''}</p>
 {#if booking.selection.powderParts.includes('Wheels / mags')}<p>Mag diameter · Front: {booking.selection.front || '—'} · Rear: {booking.selection.rear || '—'} (inches)</p>{/if}
{/if}
{#if booking.estimate}<p>Estimated service value <strong>{money(booking.estimate.total)}</strong>{#if booking.estimate.discount} · {money(booking.estimate.discount)} promo discount{/if}</p>{/if}
{#if booking.originalServices || booking.serviceChanges?.length}
 <section class="card stack" aria-label="Service history">
  <h3>Service history</h3>
  {#if booking.originalServices}
   <div>
    <strong>Original booking</strong>
    <ul>{#each labels(booking.originalServices.selection) as label}<li>{label}</li>{/each}</ul>
    {#if booking.originalServices.estimate}<p>Original estimate <strong>{money(booking.originalServices.estimate.total)}</strong></p>{/if}
   </div>
  {:else}
   <p class="small muted">Original booking details are unavailable for this older record. History starts with the first recorded edit.</p>
  {/if}
  {#each booking.serviceChanges ?? [] as change (change.id)}
   {@const before = labels(change.before.selection)}
   {@const after = labels(change.after.selection)}
   <div class="service-change">
    <strong>Changed after booking</strong>
    <p class="small muted">{change.actor} · {new Date(change.at).toLocaleString('en-PH', {timeZone:'Asia/Manila', dateStyle:'medium', timeStyle:'short', hour12:true})} PH time</p>
    <ul>
     {#each after.filter(label => !before.includes(label)) as label}<li><strong>Added</strong> {label}</li>{/each}
     {#each before.filter(label => !after.includes(label)) as label}<li><strong>Removed</strong> {label}</li>{/each}
    </ul>
    {#if change.after.estimate}<p>Estimate {change.before.estimate ? money(change.before.estimate.total) + ' → ' : ''}<strong>{money(change.after.estimate.total)}</strong></p>{/if}
   </div>
  {/each}
 </section>
{/if}
{#if booking.approvalNote}<p>Note from the shop: {booking.approvalNote}</p>{/if}
{#if booking.completionNote}<p>Completion notes: {booking.completionNote}</p>{/if}
{#if booking.photos?.length}
 <div class="cols">{#each booking.photos as photo, i}<img src={photo} alt={'Completion photo ' + (i + 1)} loading="lazy" />{/each}</div>
{/if}
{#if staff && booking.walkIn}<p>Walk-in intake · {booking.walkIn.version} · Signed by {booking.walkIn.signer} on {new Date(booking.walkIn.at).toLocaleString('en-PH', {timeZone:'Asia/Manila', hour12:true})}</p>{/if}
{#if events.length}
 <details><summary>Activity · Philippine time</summary>
  <ul>{#each events as event (event.id)}<li>{new Date(event.at).toLocaleString('en-PH', {timeZone:'Asia/Manila', dateStyle:'medium', timeStyle:'short', hour12:true})} · {event.action} · {event.actor}</li>{/each}</ul>
 </details>
{/if}
<style>
 img { width: 100%; max-height: 220px; object-fit: contain; background: var(--panel-2); border-radius: 6px; }
 ul { margin-block: 4px; padding-inline-start: 22px; }
 .service-change { padding-top: 12px; border-top: 1px solid var(--line); }
</style>
