<script lang="ts">
 import { resolve } from '$app/paths';
 import { estimatePrice, linePrice, money, serviceLabel } from '../shared/coating';
 import { serviceOf } from '../shared/config';
 import { addDays, fmtDate, fmtSlot, today } from '../shared/dates';
 import BookMenu from '../shared/BookMenu.svelte';
 import PageHeader from '../shared/PageHeader.svelte';
 import { pageCount } from '../shared/paging';
 import RecordFilterBar from '../shared/RecordFilterBar.svelte';
 import ReportDetails, { type Detail } from '../shared/ReportDetails.svelte';
 import ReportSummary from '../shared/ReportSummary.svelte';
 import ReportTable from '../shared/ReportTable.svelte';
 import { rangeIssue, servicesLine, type RecordFilters } from '../shared/records-ui';
 import { manilaStamp, reportPrice, sortReportRows, type ReportRow, type ReportSort } from '../shared/report-ui';
 import DemoBookingChanges from './DemoBookingChanges.svelte';
 import DemoReportActions from './DemoReportActions.svelte';
 import DemoServiceEdits, { editGrants } from './DemoServiceEdits.svelte';
 import { editRights } from '../shared/booking-changes';
 import { canPerform } from './staffAccess.svelte.ts';
 import { db, type Booking } from './store.svelte';
 let { showIncome = false }: { showIncome?: boolean } = $props();

 const dateOptions = { month: 'short', day: 'numeric', year: 'numeric' } as const;
 const shopDate = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Manila' });
 const shopToday = today();
 const periods = [{ value: 'all', label: 'All dates' }, { value: 'today', label: 'Today' },
  { value: 'week', label: 'Last 7 days' }, { value: 'month', label: 'This month' }, { value: 'custom', label: 'Custom range' }];
 const defaults = (): RecordFilters => ({ preset: 'all', from: shopToday.slice(0, 7) + '-01', through: shopToday, exact: shopToday, search: '', status: 'all', source: 'all' });

 const pageSize = 10;
 let recordPage = $state(1);
 let filters = $state<RecordFilters>(defaults());
 let sort = $state<ReportSort>('date');
 let detailId = $state('');
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

 function toRow(booking: Booking): ReportRow {
  const estimate = booking.originalServices?.estimate ?? booking.estimate;
  const final = booking.status === 'done' && booking.finalPrice !== undefined ? booking.finalPrice : undefined;
  const price = reportPrice(booking.status, final === undefined ? null : money(final), estimate ? estimatePrice(estimate) : null);
  return { id: booking.id, ref: booking.id, name: booking.name || 'Unnamed booking', bike: booking.bike, walkIn: Boolean(booking.walkIn), phone: booking.phone,
   date: fmtDate(booking.date, dateOptions), time: fmtSlot(booking.slot), services: servicesLine('', booking.estimate?.lines?.length ?? 1), status: booking.status,
   price: showIncome ? price.text : undefined, priceKind: price.kind, priceValue: price.kind === 'final' ? final : price.kind === 'estimate' ? estimate?.total : undefined };
 }
 const allRows = $derived(sortReportRows(rows.map(({ booking }) => toRow(booking)), sort));
 const pages = $derived(pageCount(allRows.length, pageSize));
 const currentPage = $derived(Math.min(recordPage, pages));
 const listRows = $derived(allRows.slice((currentPage - 1) * pageSize, currentPage * pageSize));
 const scheduled = $derived(rows.filter(row => row.scheduledInPeriod));
 const completed = $derived(rows.filter(row => row.completedInPeriod));
 const walkIns = $derived(scheduled.filter(({ booking }) => booking.walkIn));
 const cancelled = $derived(scheduled.filter(({ booking }) => booking.status === 'cancelled'));
 const pending = $derived(scheduled.filter(({ booking }) => booking.status === 'pending').length);
 const booked = $derived(scheduled.filter(({ booking }) => booking.status === 'confirmed').length);
 const income = $derived(completed.reduce((cents, { booking }) => cents + Math.round((booking.finalPrice ?? 0) * 100), 0) / 100);
 const bookLinks = [{ label: 'Walk-in', href: resolve('/book?manual=1&walk-in=1') }, { label: 'Online', href: resolve('/book?manual=1') }];

 const opened = $derived(db.bookings.find(item => item.id === detailId));
 const detail = $derived<Detail | undefined>(opened && {
  name: opened.name || 'Unnamed booking', ref: opened.id, status: opened.status, walkIn: Boolean(opened.walkIn), bike: opened.bike,
  lines: opened.estimate?.lines?.map(line => ({ label: line.label, price: showIncome ? linePrice(line) : undefined }))
   ?? [{ label: opened.selection ? serviceLabel(opened.selection) : serviceOf(opened.serviceId).name }],
  total: showIncome && opened.estimate ? estimatePrice(opened.estimate) : undefined,
  phone: opened.phone || undefined, email: opened.email || undefined,
  visit: fmtDate(opened.date) + ' · ' + fmtSlot(opened.slot), booked: manilaStamp(opened.createdAt ?? opened.walkIn?.at),
  approved: manilaStamp(opened.approvedAt), completed: manilaStamp(opened.status === 'done' ? opened.completedAt : undefined)
 });
 const canEditLines = $derived(Boolean(opened?.estimate?.lines?.length && (editRights(opened.status, editGrants()).price || editRights(opened.status, editGrants()).services)));
 function resetFilters() {
  recordPage = 1;
  filters = defaults();
 }
</script>

<PageHeader title="Booking reports" subtitle="Review booking records and completed service value." timezone>
 {#if canPerform('createBooking')}<BookMenu links={bookLinks} />{/if}
</PageHeader>
<div class="stack">
 <div class="card"><RecordFilterBar bind:filters {periods} showSearch={false} onchange={() => recordPage = 1} onreset={resetFilters} /></div>

{#if validRange}
 <ReportSummary income={showIncome ? money(income) : null} counts={{ total: scheduled.length, completed: completed.length, pending, booked, walkIns: walkIns.length, cancelled: cancelled.length }} />
 <ReportTable rows={listRows} total={rows.length} page={currentPage} {pages} showPrice={showIncome} selectedId={detailId} bind:sort bind:search={filters.search} sortAll
  onsearch={() => recordPage = 1} onreset={resetFilters} onDetails={(id) => detailId = id} onpage={(next) => recordPage = next} />
{/if}
</div>

{#if detail && opened}
 <ReportDetails {detail} onclose={() => detailId = ''} services={canEditLines ? lineEditor : undefined} changes={changeList}>
  {#snippet actions()}<DemoReportActions booking={opened} ondone={() => detailId = ''} />{/snippet}
 </ReportDetails>
{/if}

{#snippet lineEditor()}{#if opened}<DemoServiceEdits booking={opened} showMoney={showIncome} />{/if}{/snippet}
{#snippet changeList()}{#if opened}<DemoBookingChanges booking={opened} showMoney={showIncome} />{/if}{/snippet}
