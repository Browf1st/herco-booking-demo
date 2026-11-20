<script lang="ts">
 import { onMount, tick } from 'svelte';
 import ActionIcon from './ActionIcon.svelte';
 import ServerSharedBookingDetails from './ServerSharedBookingDetails.svelte';
 import BookingServiceEditor from './BookingServiceEditor.svelte';
 import { resolve } from '$app/paths';
 import { fmtDate, fmtSlot, today } from '#lib/dates.ts';
 import ServerCustomerChangeForm from '#lib/ServerCustomerChangeForm.svelte';
 import ServerBookingActivity from '#lib/ServerBookingActivity.svelte';
 import CoatingOptionSummary from './CoatingOptionSummary.svelte';
 import type { CoatingOptions } from './booking-coating';

 import { displayEstimate, displayServicePrice, type PricedService } from './service-estimate';
 type Service = PricedService & { code: string; label: string;
  promotion?: { label: string; base_price_centavos: number } | null };
 type Booking = {
  id: string;
  reference_no: number;
  approved_at: string|null; completed_at:string|null;cancelled_at:string|null;
  visit_date: string;
  visit_hour: number | null;
  bike: string;
  status: 'pending' | 'confirmed' | 'done' | 'cancelled';
  original_services: Service[];
  original_total_centavos: number;
  current_services: Service[] | null;
  current_total_centavos: number | null;
  coating_options?: CoatingOptions;
  created_at: string;
 };
 const labels = { pending: 'Pending', confirmed: 'Booked', done: 'Completed', cancelled: 'Cancelled' };
 const price = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
 const stamp = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' });
 type Change = {
  id: string;
  booking_id: string;
  kind: 'cancel' | 'reschedule';
  reason: string;
  state: 'pending' | 'approved' | 'declined' | 'withdrawn';
  target_date: string | null;
  target_hour: number | null;
 };
 let bookings = $state<Booking[]>([]);
 let changes = $state<Change[]>([]);
 let changeStatus = $state<'loading' | 'ready' | 'failed'>('loading');
 let requestDialog=$state<HTMLDialogElement>();
 let opened=$state<Set<string>>(new Set());
 async function openRequest(id:string,kind:Change['kind']){activeForm={id,kind};await tick();requestDialog?.showModal();}
 let activeForm = $state<{ id: string; kind: Change['kind'] }>();
 let changeNotice = $state('');
 let changeError = $state('');
 let withdrawing = $state<string>();
 let changeLoadId = 0;
 let page = $state(1);
 let hasMore = $state(false);
 let loading = $state(true);
 let signedOut = $state(false);
 let message = $state('');

 async function load(nextPage: number, signal?: AbortSignal) {
  loading = true;
  message = '';
  activeForm = undefined;
  changeNotice = '';
  changeError = '';
  changeLoadId++;
  try {
   const response = await fetch(resolve('/api/bookings') + '?page=' + nextPage, { signal });
   if (response.status === 401) {
    bookings = [];
    signedOut = true;
    return;
   }
   if (!response.ok) throw new Error();
   const data = await response.json();
   bookings = data.bookings;
   hasMore = data.hasMore;
   page = nextPage;
   signedOut = false;
   void loadChanges(bookings, signal);
  } catch {
   if (!signal?.aborted) message = 'Your bookings are temporarily unavailable. Please try again.';
  } finally {
   loading = false;
  }
 }

 async function loadChanges(items: Booking[], signal?: AbortSignal) {
  const loadId = ++changeLoadId;
  changes = [];
  changeStatus = 'loading';
  if (!items.length) {
   changeStatus = 'ready';
   return;
  }
  const query = new URLSearchParams();
  for (const booking of items) query.append('booking', booking.id);
  try {
   const response = await fetch(resolve('/api/bookings/requests') + '?' + query, { signal });
   if (!response.ok) throw new Error();
   const result = await response.json();
   if (loadId !== changeLoadId) return;
   changes = result;
   changeStatus = 'ready';
  } catch {
   if (!signal?.aborted && loadId === changeLoadId) changeStatus = 'failed';
  }
 }

 function changeSaved() {
  requestDialog?.close();
  activeForm = undefined;
  changeNotice = 'Request sent. Your current slot stays booked while the shop reviews it.';
  void loadChanges(bookings);
 }

 async function withdraw(request: Change) {
  if (withdrawing) return;
  withdrawing = request.id;
  changeNotice = changeError = '';
  try {
   const response = await fetch(resolve('/api/bookings/requests'), {
    method: 'PATCH', headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ requestId: request.id })
   });
   if (response.status === 409) void loadChanges(bookings);
   if (!response.ok) {
    const detail = await response.json().catch(() => null);
    throw new Error(detail?.message ?? 'Could not confirm withdrawal. Try again.');
   }
   changeNotice = 'Request withdrawn. Your booking is unchanged.';
   await loadChanges(bookings);
  } catch (error) {
   changeError = error instanceof Error ? error.message : 'Could not confirm withdrawal. Try again.';
  } finally {
   withdrawing = undefined;
  }
 }

 function upcoming(booking: Booking) {
  if (booking.visit_hour === null) return booking.visit_date === today();
  const hour = String(booking.visit_hour).padStart(2, '0');
  return Date.parse(booking.visit_date + 'T' + hour + ':00:00+08:00') > Date.now();
 }

 onMount(() => {
  const controller = new AbortController();
  void load(1, controller.signal);
  return () => controller.abort();
 });
</script>

<svelte:head><title>My bookings | HERCO</title></svelte:head>
<section class="section wrap stack">
 <h1>My bookings</h1>
 {#if changeNotice}<p role="status">{changeNotice}</p>{/if}
 {#if changeError}<p role="alert">{changeError}</p>{/if}
 {#if signedOut}
  <p>Sign in to see your bookings.</p>
  <div><a class="btn sm" href={resolve('/account')}>Sign in</a></div>
 {:else if loading}
  <p role="status">Loading bookings…</p>
 {:else if message}
  <p role="alert">{message}</p>
  <div><button class="btn sm ghost" onclick={() => load(page)}>Try again</button></div>
 {:else if !bookings.length}
  <p>No bookings on this page.</p>
  {#if page === 1}<div><a class="btn sm" href={resolve('/book')}>Book a visit</a></div>{/if}
 {:else}
  {#each bookings as booking (booking.id)}
   {@const requests = changes.filter(change => change.booking_id === booking.id)}
   {@const pending = requests.find(change => change.state === 'pending')}
   {@const services = booking.current_services ?? booking.original_services}
   <article class="card stack">
    <div class="row between">
     <div class="row">
      <h2>{booking.reference_no?'HG-'+booking.reference_no:booking.id}</h2>
      <span class="badge" data-status={booking.status === 'confirmed' ? 'booked' : booking.status}>{labels[booking.status]}</span>
     </div>
     {#if booking.visit_hour !== null && changeStatus === 'ready' && !pending && upcoming(booking) && (booking.status === 'pending' || booking.status === 'confirmed')}
      <div class="row">
       <button class="btn sm ghost" onclick={() => openRequest(booking.id,'cancel')}><ActionIcon name="block"/>Request cancellation</button>
       <button class="btn sm ghost" onclick={() => openRequest(booking.id,'reschedule')}><ActionIcon name="calendar"/>Request rescheduling</button>
      </div>
     {/if}
    </div>
    <p><ActionIcon name="box"/> <strong>{services.map(service => service.label).join(' · ')}</strong> · {booking.bike}</p>
    {#if booking.visit_hour === null}
     <p><strong>Walk-in</strong> · {fmtDate(booking.visit_date)} Philippine time</p>
     {#if booking.status === 'pending' || booking.status === 'confirmed'}<p class="small muted">Ask the shop if you need to change or cancel this walk-in.</p>{/if}
    {:else}
     <p><strong>Visit</strong> · {fmtDate(booking.visit_date)} at {fmtSlot(booking.visit_hour + ':00')} Philippine time</p>
    {/if}
    <p>Estimated service value <strong>{displayEstimate(services, booking.current_total_centavos ?? booking.original_total_centavos)}</strong></p>
    {#if pending}
     <div class="row between">
      <p class="small muted">{pending.kind === 'cancel' ? 'Cancellation' : 'Reschedule'} request pending. Your current slot stays booked.</p>
      <button class="btn sm ghost" disabled={!!withdrawing} onclick={() => withdraw(pending)}>Withdraw request</button>
     </div>
    {/if}
    <details ontoggle={event=>{if(event.currentTarget.open)opened=new Set([...opened,booking.id]);}}>
     <summary>View details</summary>
     <div class="stack">
      <p>Reference <strong>{booking.id}</strong></p>
      <div class="cols" aria-label="Booking dates in Philippine time"><p><ActionIcon name="clock"/> <strong>Booked on</strong><br/>{stamp.format(new Date(booking.created_at))}</p><p><ActionIcon name="check"/> <strong>Approved</strong><br/>{booking.approved_at?stamp.format(new Date(booking.approved_at)):'Awaiting approval'}</p><p><ActionIcon name="finish"/> <strong>Completed</strong><br/>{booking.completed_at?stamp.format(new Date(booking.completed_at)):'Not completed'}</p></div>
      <CoatingOptionSummary options={booking.coating_options} />
      <ul>
       {#each services as service (service.code)}
        <li>
         {service.label} · {displayServicePrice(service)}
         {#if service.promotion}
          <small class="muted">({service.promotion.label}, regular {price.format(service.promotion.base_price_centavos / 100)})</small>
         {/if}
        </li>
       {/each}
      </ul>
      {#if opened.has(booking.id)}<BookingServiceEditor bookingId={booking.id} fromStaff={false} embedded/><ServerSharedBookingDetails bookingId={booking.id}/>{/if}
      <ServerBookingActivity bookingId={booking.id} />
      {#if requests.length}
       <h3>Change requests</h3>
       <ul>
        {#each requests as request (request.id)}
         <li>
          {request.kind === 'cancel' ? 'Cancellation' : 'Rescheduling'} · {request.state}
          {#if request.target_date && request.target_hour !== null}
           · {fmtDate(request.target_date)} at {fmtSlot(request.target_hour + ':00')}
          {/if}
          {#if request.reason}<p class="small">{request.reason}</p>{/if}
         </li>
        {/each}
       </ul>
      {/if}
     </div>
    </details>
   </article>
  {/each}
 {/if}
 {#if !loading && changeStatus === 'failed'}
  <p role="alert">Change requests are temporarily unavailable. <button class="btn sm ghost" onclick={() => loadChanges(bookings)}>Try again</button></p>
 {/if}
 {#if !signedOut && !loading && !message && (page > 1 || hasMore)}
  <nav class="row" aria-label="Booking pages">
   <button class="btn sm ghost" disabled={page === 1} onclick={() => load(page - 1)}>Previous</button>
   <span>Page {page}</span>
   <button class="btn sm ghost" disabled={!hasMore} onclick={() => load(page + 1)}>Next</button>
  </nav>
 {/if}
</section>
<dialog bind:this={requestDialog} aria-label="Request a booking change">{#if activeForm}{#key activeForm.id+activeForm.kind}<ServerCustomerChangeForm bookingId={activeForm.id} kind={activeForm.kind} onSaved={changeSaved} onClose={()=>{requestDialog?.close();activeForm=undefined;}}/>{/key}{/if}</dialog>
<style>
 h2 { font-size: 1.8rem; }
 dialog{width:min(570px,calc(100% - 24px));max-height:90dvh;padding:0;border:1px solid var(--line);border-radius:12px;background:var(--panel);color:var(--text)}dialog::backdrop{background:#0009}
 details > div { margin-top: .75rem; overflow-wrap: anywhere; }
</style>
