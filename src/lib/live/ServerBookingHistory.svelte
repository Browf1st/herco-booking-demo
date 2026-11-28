<script lang="ts">
 import { onMount, tick } from 'svelte';
 import ActionIcon from '../shared/ActionIcon.svelte';
 import BookingActionsMenu from './BookingActionsMenu.svelte';
 import BookingCard, { type CardFact } from '../shared/BookingCard.svelte';
 import { menuItems, type MenuItem } from './booking-menu';
 import type { CustomerBooking as Booking, CustomerChangeRequest as Change } from './server-booking-types';
 import { resolve } from '$app/paths';
 import { goto, replaceState } from '$app/navigation';
 import { fmtDate, fmtSlot, today } from '#lib/shared/dates.ts';
 import ServerCustomerChangeForm from '#lib/live/ServerCustomerChangeForm.svelte';

 import { displayEstimate } from './service-estimate';
 import { bookingWasUpdated } from '../shared/booking-changes';
 import { bookingGroupEmpty, bookingGroupLabels, bookingGroupOrder, groupBookings, initialGroup, type BookingGroup } from './booking-groups';
 const labels = { pending: 'Pending', confirmed: 'Booked', done: 'Completed', cancelled: 'Cancelled' };
 let bookings = $state<Booking[]>([]);
 let changes = $state<Change[]>([]);
 let changeStatus = $state<'loading' | 'ready' | 'failed'>('loading');
 let requestDialog=$state<HTMLDialogElement>();
 // The booking whose details popup is open.
 let viewingId = $state<string>();
 const viewing = $derived(bookings.find(booking => booking.id === viewingId));
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

 function cardFacts(booking: Booking, services: Booking['original_services']): CardFact[] {
  const count = services.length;
  return [
   { icon: 'clock', label: 'Time', value: booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00') },
   { icon: 'finish', label: 'Bike', value: booking.bike || 'Not provided' },
   { icon: 'menu', label: 'Services', value: count + (count === 1 ? ' service' : ' services') },
   { icon: 'adjust', label: 'Price', value: displayEstimate(services, booking.current_total_centavos ?? booking.original_total_centavos) }
  ];
 }

 function pick(booking: Booking, item: MenuItem, pending?: Change) {
  if (item === 'edit-service') void goto(resolve('/book') + '?edit=' + encodeURIComponent(booking.id));
  else if (item === 'view-service') editing = { id: booking.id, shopPriced: !!booking.shop_priced };
  else if (item === 'withdraw') { if (pending && confirm('Withdraw this request? Your booking stays as it is.')) void withdraw(pending); }
  else void openRequest(booking.id, item);
 }
 // The booking whose read-only service view (View service) is open. Editing happens on /book?edit=.
 let editing = $state<{ id: string; shopPriced: boolean }>();
 function openModal(node: HTMLDialogElement) { node.showModal(); }

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
   {@const updated = bookingWasUpdated({ originalTotal: booking.original_total_centavos, currentTotal: booking.current_total_centavos, originalCodes: booking.original_services.map(service => service.code), currentCodes: booking.current_services?.map(service => service.code) })}
   {@const facts = cardFacts(booking, services)}
   {@const items = menuItems({ status: booking.status, visitHour: booking.visit_hour, future: upcoming(booking), requestsReady: changeStatus === 'ready', hasOpenRequest: !!pending, shopPriced: booking.shop_priced })}
   <article class="card stack booking-article" data-status={booking.status} class:just-submitted={booking.id === submittedId}>
    <BookingCard when={fmtDate(booking.visit_date)} status={booking.status} {facts} services={services.map(service => service.code)} actionsTop onDetails={() => viewingId = booking.id}>
     {#snippet actions()}
      {#if items.length}<BookingActionsMenu id={booking.id} busy={!!withdrawing} {items} onpick={item => pick(booking, item, pending)} />{/if}
     {/snippet}
    </BookingCard>
    {#if updated && booking.shop_priced}<p class="small updated-note">Updated by the shop after inspection</p>{/if}
    {#if booking.visit_hour === null && (booking.status === 'pending' || booking.status === 'confirmed')}<p class="small muted">Ask the shop if you need to change or cancel this walk-in.</p>{/if}
    {#if pending}
     <p class="small request-warning">{pending.kind === 'cancel' ? 'Cancellation' : 'Reschedule'} request pending{pending.kind === 'reschedule' && pending.target_date && pending.target_hour !== null ? ' (to ' + fmtDate(pending.target_date) + ' at ' + fmtSlot(pending.target_hour + ':00') + ')' : ''}. Your current slot stays booked. Use Actions to withdraw it.</p>
    {/if}
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
{#if viewing}
 {#await import('./ServerCustomerBookingPopup.svelte') then { default: Popup }}
  <Popup booking={viewing} requests={changes.filter(change => change.booking_id === viewing.id)} onclose={() => viewingId = undefined} />
 {/await}
{/if}
<dialog bind:this={requestDialog} aria-label="Request a booking change">{#if activeForm}{#key activeForm.id+activeForm.kind}<ServerCustomerChangeForm bookingId={activeForm.id} kind={activeForm.kind} onSaved={changeSaved} onClose={()=>{requestDialog?.close();activeForm=undefined;}}/>{/key}{/if}</dialog>
{#if editing}
 {@const ed = editing}
 <dialog class="service-dialog" use:openModal onclose={() => editing = undefined} onclick={(event) => { if (event.target === event.currentTarget) editing = undefined; }}>
  <header><h3>View service</h3><button type="button" class="close" aria-label="Close" onclick={() => editing = undefined}>×</button></header>
  <div class="svc-body">{#await import('./BookingServiceEditor.svelte') then { default: Editor }}<Editor bookingId={ed.id} fromStaff={false} shopPriced={ed.shopPriced} readOnly embedded />{/await}</div>
 </dialog>
{/if}
<style>
 /* Owner asked for smaller type here (2026-11-20). */
 h1 { font-size: clamp(2rem, 5vw, 2.5rem); line-height: 1.05; }
 .group-tabs { display: flex; gap: 6px; overflow-x: auto; padding-bottom: 2px; }
 .group-tab { flex: none; display: inline-flex; align-items: center; gap: 6px; min-height: 40px; padding: 6px 14px; border: 1px solid var(--line); border-radius: 999px; background: var(--panel); color: var(--text); font: 650 .95rem var(--body); cursor: pointer; }
 .group-tab[aria-pressed='true'] { border-color: var(--accent); background: var(--accent); color: #fff; }
 .count { min-width: 1.5em; padding: 0 6px; border-radius: 999px; background: color-mix(in srgb, currentColor 16%, transparent); font-size: .8rem; text-align: center; }
 .booking-article { border-inline-start: 5px solid var(--line); gap: .5rem; }
 .booking-article[data-status='pending'] { border-inline-start-color: var(--warn-line); }
 .booking-article[data-status='confirmed'] { border-inline-start-color: var(--info-line); }
 .booking-article[data-status='done'] { border-inline-start-color: var(--ok-line); }
 .booking-article[data-status='cancelled'] { border-inline-start-color: var(--line); opacity: .85; }
 .request-warning { margin: 0; padding: 8px 12px; border-radius: 8px; background: var(--warn-bg); }
 .updated-note { margin: 0; padding: 6px 10px; border: 1px solid var(--info-line); border-radius: 8px; background: var(--panel-2); color: var(--text); font-weight: 650; }
 .submitted-notice { padding: .75rem 1rem; border: 1px solid var(--accent); border-radius: 8px; }
 .just-submitted { outline: 2px solid var(--accent); outline-offset: 2px; }
 dialog{width:min(570px,calc(100% - 24px));max-height:90dvh;padding:0;border:1px solid var(--line);border-radius:12px;background:var(--panel);color:var(--text)}dialog::backdrop{background:#0009}
 .service-dialog { width: min(46rem, calc(100% - 24px)); overflow: hidden; display: flex; flex-direction: column; }
 .service-dialog header { display: flex; align-items: center; justify-content: space-between; gap: .75rem; padding: .9rem 1.1rem; background: light-dark(#1b2230, #0d1218); color: #fff; }
 .service-dialog h3 { margin: 0; font-size: 1.2rem; }
 .service-dialog .close { display: grid; place-items: center; width: 2.5rem; height: 2.5rem; flex: none; padding: 0; border: 1px solid #ffffff44; border-radius: 8px; background: #ffffff1a; color: #fff; font: 400 1.6rem/1 var(--body); cursor: pointer; }
 .service-dialog .close:hover { background: #ffffff2e; }
 .service-dialog .close:focus-visible { outline: 2px solid #fff; outline-offset: 2px; }
 .svc-body { padding: 1rem 1.1rem 1.1rem; overflow-y: auto; }
 @media (max-width: 640px) { .service-dialog { width: 100%; margin: auto 0 0; border-radius: 16px 16px 0 0; } }
</style>
