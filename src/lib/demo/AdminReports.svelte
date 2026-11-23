<script lang="ts">
 import { money, serviceLabel } from '../shared/coating';
 import { serviceOf } from '../shared/config';
 import { addDays, fmtDate, fmtSlot, today } from '../shared/dates';
 import Pager from '../shared/Pager.svelte';
 import { pageCount } from '../shared/paging';
 import RecordFilterBar from '../shared/RecordFilterBar.svelte';
 import RecordsEmpty from '../shared/RecordsEmpty.svelte';
 import ReportList from '../shared/ReportList.svelte';
 import ReportSummary from '../shared/ReportSummary.svelte';
 import { rangeIssue, servicesLine, type RecordFilters, type ReportRow } from '../shared/records-ui';
 import { db, type Booking } from './store.svelte';
 let { showIncome = false, onDetails }: { showIncome?: boolean; onDetails: (booking: Booking) => void } = $props();

 const dateOptions = { month: '2-digit', day: '2-digit', year: '2-digit' } as const;
 const shopDate = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Manila' });
 const shopToday = today();
 const periods = [{ value: 'all', label: 'All dates' }, { value: 'today', label: 'Today' },
  { value: 'week', label: 'Last 7 days' }, { value: 'month', label: 'This month' }, { value: 'custom', label: 'Custom range' }];
 const defaults = (): RecordFilters => ({ preset: 'all', from: shopToday.slice(0, 7) + '-01', through: shopToday, exact: shopToday, search: '', status: 'all', source: 'all' });

 const pageSize = 10;
 let recordPage = $state(1);
 let filters = $state<RecordFilters>(defaults());
 const start = $derived(filters.preset === 'custom' ? filters.from : filters.preset === 'month' ? shopToday.slice(0, 7) + '-01' : filters.preset === 'week' ? addDays(shopToday, -6) : shopToday);
 const end = $derived(filters.preset === 'custom' ? filters.through : shopToday);
 const validRange = $derived(!rangeIssue(filters));
 const query = $derived(filters.search.trim().toLowerCase());

 function inPeriod(date: string) {
  return validRange && (filters.preset === 'all' || (date >= start && date <= end));
 }

 const periodRows = $derived(db.bookings.flatMap(booking => {
  const service = booking.selection ? serviceLabel(booking.selection) : serviceOf(booking.serviceId).name;
  if (query && ![booking.id, booking.name, booking.email, booking.phone, booking.bike, booking.plateNumber, service]
   .some(value => value?.toLowerCase().includes(query))) return [];

  const completion = booking.completedAt ? shopDate.format(new Date(booking.completedAt)) : '';
  const scheduledInPeriod = inPeriod(booking.date);
  const completedInPeriod = booking.status === 'done' && inPeriod(completion || booking.date);
  if (!scheduledInPeriod && !completedInPeriod) return [];
  return [{ booking, scheduledInPeriod, completedInPeriod, reportDate: completedInPeriod ? completion || booking.date : booking.date }];
 }));
 const rows = $derived(periodRows
  .filter(({ booking }) => (filters.source === 'all' || Boolean(booking.walkIn) === (filters.source === 'walk-in')) && (filters.status === 'all' || booking.status === filters.status))
  .toSorted((a, b) => b.reportDate.localeCompare(a.reportDate) || b.booking.slot.localeCompare(a.booking.slot)));

 const pages = $derived(pageCount(rows.length, pageSize));
 const currentPage = $derived(Math.min(recordPage, pages));
 const listRows = $derived<ReportRow[]>(rows.slice((currentPage - 1) * pageSize, currentPage * pageSize).map(({ booking }) => ({
  id: booking.id, ref: booking.id, name: booking.name, date: fmtDate(booking.date, dateOptions), time: fmtSlot(booking.slot),
  services: servicesLine('', booking.estimate?.lines?.length ?? 1), status: booking.status,
  price: booking.status === 'done' && booking.finalPrice !== undefined ? money(booking.finalPrice) : '—'
 })));
 const scheduled = $derived(rows.filter(row => row.scheduledInPeriod));
 const completed = $derived(rows.filter(row => row.completedInPeriod));
 const missingFinalPrices = $derived(completed.filter(({ booking }) => booking.finalPrice === undefined).length);
 const income = $derived(completed.reduce((cents, { booking }) => cents + Math.round((booking.finalPrice ?? 0) * 100), 0) / 100);
 const notes = $derived(['Booking counts use the scheduled date. Completed totals use the completion date, or the scheduled date when an older record has no completion timestamp.',
  ...(showIncome && missingFinalPrices ? [`Completed bookings missing a final price are excluded from income (${missingFinalPrices}).`] : [])]);
 function resetFilters() {
  recordPage = 1;
  filters = defaults();
 }
</script>

<div class="stack">
 <div class="card"><RecordFilterBar bind:filters {periods} onchange={() => recordPage = 1} onreset={resetFilters} /></div>

{#if validRange}
 <ReportSummary income={showIncome ? money(income) : null} {notes} items={[['Bookings in period', scheduled.length], ['Completed services', completed.length],
  ['Pending and booked', scheduled.filter(({ booking }) => booking.status === 'pending' || booking.status === 'confirmed').length],
  ['Walk-in bookings', scheduled.filter(({ booking }) => booking.walkIn).length],
  ['Cancelled bookings', scheduled.filter(({ booking }) => booking.status === 'cancelled').length]]} />

 <section class="stack" aria-labelledby="report-records">
  <div class="row between"><h2 id="report-records">Booking records</h2><p class="small muted" aria-live="polite">{rows.length} {rows.length === 1 ? 'record' : 'records'} · Newest first</p></div>
  {#if rows.length}
   <ReportList rows={listRows} showPrice={showIncome} onDetails={(id) => { const found = db.bookings.find(item => item.id === id); if (found) onDetails(found); }} />
   <Pager page={currentPage} {pages} label="Booking records" onchange={(next) => recordPage = next} />
  {:else}
   <RecordsEmpty title="No bookings found" text="Try another date, status or search to find your bookings." action="Reset filters" onaction={resetFilters} />
  {/if}
 </section>
{/if}
</div>

<style>
 h2 { font-size: 1.35rem; }
 .between { justify-content: space-between; }
</style>
