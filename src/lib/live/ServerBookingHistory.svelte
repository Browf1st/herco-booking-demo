<script lang="ts">
 import { onMount, tick } from 'svelte';
 import ActionIcon from '../shared/ActionIcon.svelte';
 import ServerSharedBookingDetails from './ServerSharedBookingDetails.svelte';
 import BookingServiceEditor from './BookingServiceEditor.svelte';
 import { resolve } from '$app/paths';
 import { replaceState } from '$app/navigation';
 import { fmtDate, fmtSlot, today } from '#lib/shared/dates.ts';
 import ServerCustomerChangeForm from '#lib/live/ServerCustomerChangeForm.svelte';
 import ServerBookingActivity from '#lib/live/ServerBookingActivity.svelte';
 import CoatingOptionSummary from './CoatingOptionSummary.svelte';
 import type { CoatingOptions } from './booking-coating';

 import { displayEstimate, displayServicePrice, type PricedService } from './service-estimate';
 import { bookingGroupEmpty, bookingGroupLabels, bookingGroupOrder, groupBookings, initialGroup, type BookingGroup } from './booking-groups';
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
 // Set when the booking form sends the customer here right after a successful submit.
 let submittedId = $state('');
 const submittedBooking = $derived(submittedId ? bookings.find(booking => booking.id === submittedId) : undefined);
 // Sections: Upcoming, Requests (open cancel/reschedule), Past, Cancelled. Grouped within the loaded page.
 const groups = $derived(groupBookings(bookings, new Set(changes.filter(change => change.state === 'pending').map(change => change.booking_id)), upcoming));
 let chosenGroup = $state<BookingGroup>();
 // Sections wait for the first change-request check so bookings don't jump between sections.
 let changesChecked = $state(false);
 const activeGroup = $derived(chosenGroup ?? initialGroup(groups, submittedId));

 async function load(nextPage: number, signal?: AbortSignal) {
  loading = true;
  message = '';
  activeForm = undefined;
  changeNotice = '';
  changeError = '';
  changeLoadId++;
  changes = [];
  changesChecked = false;
  if (nextPage !== page) chosenGroup = undefined;
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
  changeStatus = 'loading';
  if (!items.length) {
   changeStatus = 'ready';
   changesChecked = true;
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
   changesChecked = true;
  } catch {
   if (!signal?.aborted && loadId === changeLoadId) {
    changeStatus = 'failed';
    changesChecked = true;
   }
  }
 }

 function changeSaved() {
  requestDialog?.close();
  activeForm = undefined;
  changeNotice = 'Request sent. Your current slot stays booked while the shop reviews it.';
  chosenGroup = 'requests';
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
   chosenGroup = 'upcoming';
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
  const submitted = new URL(window.location.href).searchParams.get('submitted') ?? '';
  if (/^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i.test(submitted)) submittedId = submitted;
  // Show the "submitted" message once: drop it from the address so a refresh or bookmark doesn't repeat it.
  if (submitted) {
   try { replaceState(resolve('/my-bookings'), {}); } catch { /* router not ready: the message just shows again on refresh */ }
  }
  const controller = new AbortController();
  void load(1, controller.signal);
  return () => controller.abort();
 });
</script>

<svelte:head><title>My bookings | HERCO</title></svelte:head>
<section class="section wrap stack">
 <h1>My bookings</h1>
 {#if submittedBooking}<p role="status" class="submitted-notice"><ActionIcon name="check" /> Booking{submittedBooking.reference_no ? ' HG-' + submittedBooking.reference_no : ''} submitted. Status: <strong>{labels[submittedBooking.status]}</strong>{submittedBooking.status === 'pending' ? ' — the shop will review it and email you when it is confirmed.' : '.'}</p>{/if}
 {#if changeNotice}<p role="status">{changeNotice}</p>{/if}
 {#if changeError}<p role="alert">{changeError}</p>{/if}
 {#if signedOut}
  <p>Sign in to see your bookings.</p>
  <div><a class="btn sm" href={resolve('/account')}>Sign in</a></div>
 {:else if loading || (bookings.length && !changesChecked)}
  <p role="status">Loading bookings…</p>
 {:else if message}
  <p role="alert">{message}</p>
  <div><button class="btn sm ghost" onclick={() => load(page)}>Try again</button></div>
 {:else if !bookings.length}
  <p>No bookings on this page.</p>
  {#if page === 1}<div><a class="btn sm" href={resolve('/book')}>Book a visit</a></div>{/if}
 {:else}
  <div class="group-tabs" role="group" aria-label="Booking sections">
   {#each bookingGroupOrder as name (name)}
    <button type="button" class="group-tab" aria-pressed={activeGroup === name} onclick={() => chosenGroup = name}>
     {bookingGroupLabels[name]} <span class="count" aria-label={groups[name].length + ' bookings'}>{groups[name].length}</span>
    </button>
   {/each}
  </div>
  {#if changeStatus === 'failed'}
   <p role="alert" class="request-warning">Change requests could not be loaded, so open requests may not show and request buttons are hidden. <button class="btn sm ghost" onclick={() => loadChanges(bookings)}>Try again</button></p>
  {/if}
  {#each groups[activeGroup] as booking (booking.id)}
   {@const requests = changes.filter(change => change.booking_id === booking.id)}
   {@const pending = requests.find(change => change.state === 'pending')}
   {@const services = booking.current_services ?? booking.original_services}
   <article class="card stack booking-card" data-status={booking.status} class:just-submitted={booking.id === submittedId}>
    <div class="card-top">
     <div class="when">
      <h2>{fmtDate(booking.visit_date)}</h2>
      <p class="small muted">{booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00')} · Philippine time</p>
     </div>
     <span class="badge" data-status={booking.status === 'confirmed' ? 'booked' : booking.status}>{labels[booking.status]}</span>
    </div>
    <p class="what"><strong>{services.map(service => service.label).join(' · ')}</strong> · {booking.bike}</p>
    <p class="small muted">{booking.reference_no ? 'HG-' + booking.reference_no + ' · ' : ''}Estimated <strong>{displayEstimate(services, booking.current_total_centavos ?? booking.original_total_centavos)}</strong></p>
    {#if booking.visit_hour === null && (booking.status === 'pending' || booking.status === 'confirmed')}<p class="small muted">Ask the shop if you need to change or cancel this walk-in.</p>{/if}
    {#if pending}
     <div class="request-note">
      <p class="small">{pending.kind === 'cancel' ? 'Cancellation' : 'Reschedule'} request pending{pending.kind === 'reschedule' && pending.target_date && pending.target_hour !== null ? ' (to ' + fmtDate(pending.target_date) + ' at ' + fmtSlot(pending.target_hour + ':00') + ')' : ''}. Your current slot stays booked.</p>
      <button class="btn sm ghost" disabled={!!withdrawing} onclick={() => withdraw(pending)}>Withdraw request</button>
     </div>
    {/if}
    {#if booking.visit_hour !== null && changeStatus === 'ready' && !pending && upcoming(booking) && (booking.status === 'pending' || booking.status === 'confirmed')}
     <div class="row actions">
      <button class="btn sm ghost" onclick={() => openRequest(booking.id,'reschedule')}><ActionIcon name="calendar"/>Request rescheduling</button>
      <button class="btn sm ghost" onclick={() => openRequest(booking.id,'cancel')}><ActionIcon name="block"/>Request cancellation</button>
     </div>
    {/if}
    <details ontoggle={event=>{if(event.currentTarget.open)opened=new Set([...opened,booking.id]);}}>
     <summary>{booking.status === 'pending' && upcoming(booking) ? 'View details or edit services' : 'View details'}</summary>
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
  {:else}
   <p class="muted">{bookingGroupEmpty[activeGroup]}</p>
   {#if activeGroup === 'upcoming' && page === 1}<div><a class="btn sm" href={resolve('/book')}>Book a visit</a></div>{/if}
  {/each}
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
 /* Owner asked for smaller type here (2026-11-20). */
 h1 { font-size: clamp(2rem, 5vw, 2.5rem); line-height: 1.05; }
 h2 { font: 750 1.15rem/1.2 var(--body); font-style: normal; text-transform: none; }
 h3 { font-size: 1.05rem; }
 .group-tabs { display: flex; gap: 6px; overflow-x: auto; padding-bottom: 2px; }
 .group-tab { flex: none; display: inline-flex; align-items: center; gap: 6px; min-height: 40px; padding: 6px 14px; border: 1px solid var(--line); border-radius: 999px; background: var(--panel); color: var(--text); font: 650 .95rem var(--body); cursor: pointer; }
 .group-tab[aria-pressed='true'] { border-color: var(--accent); background: var(--accent); color: #fff; }
 .count { min-width: 1.5em; padding: 0 6px; border-radius: 999px; background: color-mix(in srgb, currentColor 16%, transparent); font-size: .8rem; text-align: center; }
 .booking-card { border-inline-start: 5px solid var(--line); gap: .5rem; }
 .booking-card[data-status='pending'] { border-inline-start-color: var(--warn-line); }
 .booking-card[data-status='confirmed'] { border-inline-start-color: var(--info-line); }
 .booking-card[data-status='done'] { border-inline-start-color: var(--ok-line); }
 .booking-card[data-status='cancelled'] { border-inline-start-color: var(--line); opacity: .85; }
 .card-top { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; }
 .when p, .what { margin: 0; }
 .request-note { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 8px; padding: 8px 12px; border-radius: 8px; background: var(--warn-bg); }
 .request-note p { margin: 0; }
 .actions { flex-wrap: wrap; }
 .request-warning { padding: 8px 12px; border-radius: 8px; background: var(--warn-bg); }
 summary { cursor: pointer; font-weight: 650; }
 .submitted-notice { padding: .75rem 1rem; border: 1px solid var(--accent); border-radius: 8px; }
 .just-submitted { outline: 2px solid var(--accent); outline-offset: 2px; }
 dialog{width:min(570px,calc(100% - 24px));max-height:90dvh;padding:0;border:1px solid var(--line);border-radius:12px;background:var(--panel);color:var(--text)}dialog::backdrop{background:#0009}
 details > div { margin-top: .75rem; overflow-wrap: anywhere; }
</style>
