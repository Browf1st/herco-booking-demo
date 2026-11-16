<script lang="ts">
 import ActionIcon from '#lib/ActionIcon.svelte';
 import { money, serviceLabel } from './coating';
 import { serviceOf } from './config';
 import { addDays, fmtDate, fmtSlot, today } from './dates';
 import { bookingStatusLabels, db, type Status } from './store.svelte';
 let { owner = false }: { owner?: boolean } = $props();

 const dateOptions = { month: '2-digit', day: '2-digit', year: '2-digit' } as const;
 const shopDate = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Manila' });
 const shopToday = today();
 const presets = [{ value: 'all', label: 'All dates' }, { value: 'today', label: 'Today' },
  { value: 'week', label: 'Last 7 days' }, { value: 'month', label: 'This month' }, { value: 'custom', label: 'Custom range' }] as const;
 type Preset = typeof presets[number]['value'];

 let preset = $state<Preset>('all');
 const pageSize = 10;
 let recordPage = $state(1);
 let from = $state(shopToday.slice(0, 7) + '-01');
 let to = $state(shopToday);
 let status = $state<Status | 'all'>('all');
 let source = $state('all');
 let search = $state('');
 const start = $derived(preset === 'custom' ? from : preset === 'month' ? shopToday.slice(0, 7) + '-01' : preset === 'week' ? addDays(shopToday, -6) : shopToday);
 const end = $derived(preset === 'custom' ? to : shopToday);
 const validRange = $derived(preset !== 'custom' || Boolean(from && to && from <= to));
 const query = $derived(search.trim().toLowerCase());

 function inPeriod(date: string) {
  return validRange && (preset === 'all' || (date >= start && date <= end));
 }

 function resetFilters() {
  recordPage = 1;
  preset = 'all';
  from = shopToday.slice(0, 7) + '-01';
  to = shopToday;
  status = 'all';
  source = 'all';
  search = '';
 }

 const periodRows = $derived(db.bookings.flatMap(booking => {
  const service = booking.selection ? serviceLabel(booking.selection) : serviceOf(booking.serviceId).name;
  if (query && ![booking.id, booking.name, booking.email, booking.phone, booking.bike, booking.plateNumber, service]
   .some(value => value?.toLowerCase().includes(query))) return [];

  const completion = booking.completedAt ? shopDate.format(new Date(booking.completedAt)) : '';
  const scheduledInPeriod = inPeriod(booking.date);
  const completedInPeriod = booking.status === 'done' && inPeriod(completion || booking.date);
  if (!scheduledInPeriod && !completedInPeriod) return [];
  return [{ booking, service, completion, scheduledInPeriod, completedInPeriod, reportDate: completedInPeriod ? completion || booking.date : booking.date }];
 }));
 const statusRows = $derived(periodRows.filter(({ booking }) => source === 'all' || Boolean(booking.walkIn) === (source === 'walk-in')));
 const sourceRows = $derived(periodRows.filter(({ booking }) => status === 'all' || booking.status === status));
 const rows = $derived(statusRows.filter(({ booking }) => status === 'all' || booking.status === status)
  .toSorted((a, b) => b.reportDate.localeCompare(a.reportDate) || b.booking.slot.localeCompare(a.booking.slot)));

 const pages = $derived(Math.max(1, Math.ceil(rows.length / pageSize)));
 const currentPage = $derived(Math.min(recordPage, pages));
 const pageRows = $derived(rows.slice((currentPage - 1) * pageSize, currentPage * pageSize));
 const scheduled = $derived(rows.filter(row => row.scheduledInPeriod));
 const completed = $derived(rows.filter(row => row.completedInPeriod));
 const missingFinalPrices = $derived(completed.filter(({ booking }) => booking.finalPrice === undefined).length);
 const income = $derived(completed.reduce((cents, { booking }) => cents + Math.round((booking.finalPrice ?? 0) * 100), 0) / 100);
 const metrics = $derived([
  ...(owner ? [['Total income from completed services', money(income), 'income']] : []),
  ['Bookings in period', scheduled.length],
  ['Completed services', completed.length, 'completed'],
  ['Pending and booked', scheduled.filter(({ booking }) => booking.status === 'pending' || booking.status === 'confirmed').length],
  ['Walk-in bookings', scheduled.filter(({ booking }) => booking.walkIn).length],
  ['Cancelled bookings', scheduled.filter(({ booking }) => booking.status === 'cancelled').length, 'cancelled']
 ]);
</script>

<div class="report-layout">
<section class="card stack report-panel" aria-labelledby="reports-title">
 <div class="row report-toolbar">
  <h3 id="reports-title">Booking reports</h3>
  <div class="row report-actions">
  <div class="report-period" role="group" aria-label="Report period">
   {#each presets as option (option.value)}
    <button type="button" aria-pressed={preset === option.value} onclick={() => { preset = option.value; recordPage = 1; }}><ActionIcon name="calendar" />{option.label}</button>
   {/each}
  </div>
  <button type="button" class="report-reset" onclick={resetFilters}><ActionIcon name="reset" />Reset filters</button>
  </div>
 </div>
 {#if preset === 'custom'}
  <div class="cols">
   <label>From<input type="date" bind:value={from} oninput={() => recordPage = 1} /></label>
   <label>To<input type="date" bind:value={to} oninput={() => recordPage = 1} /></label>
  </div>
 {/if}
 <div class="report-filters">
  <label>Search bookings<input type="search" bind:value={search} oninput={() => recordPage = 1} placeholder="Name, reference, bike or service" /></label>
  <label>Status<select bind:value={status} onchange={() => recordPage = 1}>
   <option value="all">All statuses ({statusRows.length})</option>
   {#each Object.entries(bookingStatusLabels) as [value, label] (value)}<option {value}>{label} ({statusRows.filter(({ booking }) => booking.status === value).length})</option>{/each}
  </select></label>
  <label>Booking source<select bind:value={source} onchange={() => recordPage = 1}>
   <option value="all">All sources ({sourceRows.length})</option><option value="online">Online ({sourceRows.filter(({ booking }) => !booking.walkIn).length})</option><option value="walk-in">Walk-in ({sourceRows.filter(({ booking }) => booking.walkIn).length})</option>
  </select></label>
 </div>
 {#if !validRange}<p class="error" role="alert">Choose a start and end date in order.</p>{/if}
</section>

{#if validRange}
 <dl class="report-metrics">
  {#each metrics as [label, value, metric] (label)}
   <div class="card" data-metric={metric}><dt class="muted">{label}</dt><dd>{value}</dd></div>
  {/each}
 </dl>

 <section class="card stack report-panel" aria-labelledby="report-records">
  <div class="row between">
   <div class="row"><h3 id="report-records">Booking records</h3><p class="small muted" aria-live="polite">{rows.length} {rows.length === 1 ? 'record' : 'records'}</p></div>
   <p class="small muted">Philippine time · Newest first</p>
  </div>
  <p class="small muted">All dates use Philippine time. Booking counts use the scheduled date. Completed totals use the completion date, or the scheduled date when an older record has no completion timestamp.</p>
  {#if owner && missingFinalPrices}
   <p class="small muted">Completed bookings missing a final price are excluded from income ({missingFinalPrices}).</p>
  {/if}
  {#if rows.length}
   <!-- svelte-ignore a11y_no_noninteractive_tabindex (Keyboard users need to scroll the table horizontally.) -->
   <div class="report-table" role="region" aria-labelledby="report-records" tabindex="0">
    <table>
     <thead><tr><th scope="col">Booking</th><th scope="col">Service</th><th scope="col">Scheduled</th><th scope="col">Completed</th><th scope="col">Status</th><th scope="col">Source</th>{#if owner}<th scope="col" class="report-price">Final price</th>{/if}</tr></thead>
     <tbody>
      {#each pageRows as { booking, service, completion } (booking.id)}
       <tr>
        <td><strong>{booking.name}</strong><div class="small muted">{booking.id}</div></td>
        <td>{service}<div class="small muted">{booking.bike}</div></td>
        <td class="report-visit">
         <time datetime={booking.date}>{fmtDate(booking.date, dateOptions)}</time>
         <div class="small muted">{fmtSlot(booking.slot)}</div>
        </td>
        <td>{#if completion}<time datetime={completion}>{fmtDate(completion, dateOptions)}</time>{:else}—{/if}</td>
        <td><span class="badge" data-status={booking.status === 'confirmed' ? 'booked' : booking.status}>{bookingStatusLabels[booking.status]}</span></td>
        <td>{booking.walkIn ? 'Walk-in' : 'Online'}</td>
        {#if owner}<td class="report-price">{booking.status === 'done' && booking.finalPrice !== undefined ? money(booking.finalPrice) : '—'}</td>{/if}
       </tr>
      {/each}
     </tbody>
    </table>
   </div>
   {#if pages > 1}
    <nav class="row" aria-label="Booking records pagination">
     <button type="button" class="btn sm ghost" disabled={currentPage === 1} onclick={() => recordPage = currentPage - 1}><ActionIcon name="left" />Previous</button>
     <span class="small muted" aria-live="polite">Page {currentPage} of {pages}</span>
     <button type="button" class="btn sm ghost" disabled={currentPage === pages} onclick={() => recordPage = currentPage + 1}><ActionIcon name="right" />Next</button>
    </nav>
   {/if}
  {:else}
   <p class="muted">No booking records match these filters.</p>
  {/if}
 </section>
{/if}
</div>

<style>
 .report-layout { display: grid; gap: 1rem; min-width: 0; }
 .report-panel { gap: .85rem; min-width: 0; }
 .report-toolbar { align-items: center; justify-content: space-between; border-bottom: 1px solid var(--line); padding-bottom: .7rem; }
 .report-actions { align-items: center; gap: .5rem; }
 .report-period { display: flex; flex-wrap: wrap; gap: .15rem; padding: .2rem; background: var(--panel-2); border: 1px solid var(--line); border-radius: .35rem; }
 .report-period button, .report-reset { font: inherit; font-size: .75rem; font-weight: 750; text-transform: uppercase; padding: .35rem .55rem; border: 1px solid transparent; border-radius: .25rem; cursor: pointer; color: var(--text); background: transparent; }
 .report-period button[aria-pressed="true"] { color: var(--accent-ink); background: var(--accent-fill); }
 .report-period button:hover[aria-pressed="false"], .report-reset:hover { background: var(--panel-2); border-color: var(--line); }
 .report-reset { color: var(--accent); border-color: var(--line); }
 .report-filters { display: grid; grid-template-columns: 2fr 1fr 1fr; gap: .75rem; }
 .report-filters input, .report-filters select { padding-block: .45rem; }
 .report-metrics { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .75rem; margin: 0; }
 .report-metrics > div { display: flex; flex-direction: column; justify-content: space-between; padding: .85rem; }
 .report-metrics dt, th { font-size: .75rem; font-weight: 700; letter-spacing: .04em; text-transform: uppercase; }
 .report-metrics dd { margin: .4rem 0 0; font-size: 1.5rem; font-weight: 750; font-variant-numeric: tabular-nums; }
 .report-metrics [data-metric="completed"] dd, .report-metrics [data-metric="income"] dd { color: var(--ok); }
 .report-metrics [data-metric="cancelled"] dd { color: var(--accent); }
 .report-table { overflow-x: auto; border: 1px solid var(--line); border-radius: .35rem; }
 table { width: 100%; min-width: 920px; border-collapse: collapse; }
 th, td { padding: .6rem .7rem; text-align: left; vertical-align: top; border-bottom: 1px solid var(--line); }
 th, tbody tr:nth-child(even) { background: var(--panel-2); }
 tbody tr:last-child td { border-bottom: 0; }
 .report-price { text-align: right; font-variant-numeric: tabular-nums; }
 .report-visit, td:nth-child(n+4) { white-space: nowrap; }
 @media (max-width: 850px) { .report-metrics { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
 @media (max-width: 570px) { .report-filters { grid-template-columns: minmax(0, 1fr); } }
</style>
