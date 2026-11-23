<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { addDays, fmtDate, fmtSlot, today } from '../shared/dates';
	import DetailsSheet from '../shared/DetailsSheet.svelte';
	import PageHeader from '../shared/PageHeader.svelte';
	import Pager from '../shared/Pager.svelte';
	import RecordFilterBar from '../shared/RecordFilterBar.svelte';
	import RecordsEmpty from '../shared/RecordsEmpty.svelte';
	import ReportList from '../shared/ReportList.svelte';
	import ReportSummary from '../shared/ReportSummary.svelte';
	import StatusTiles from '../shared/StatusTiles.svelte';
	import { rangeIssue, servicesLine, statusLabels, type RecordFilters, type ReportRow } from '../shared/records-ui';
	import ServerBookingDetails from './ServerBookingDetails.svelte';
	import ServerStaffBookingCard from './ServerStaffBookingCard.svelte';
	import type { StaffBooking } from './server-booking-types';
	let { report = false }: { report?: boolean } = $props();
	type Result = { records: StaffBooking[]; metrics: { total: number; pending: number; booked: number; completed: number; cancelled: number; walkIns: number; completedValueCentavos?: number | null; completedWithoutValue?: number }; total: number; pages: number; canViewIncome: boolean };
	const periods = [{ value: 'all', label: 'All dates' }, { value: 'today', label: 'Today' }, { value: 'week', label: 'Last 7 days' }, { value: 'month', label: 'This month' }, { value: 'date', label: 'Specific date' }, { value: 'custom', label: 'Custom range' }];
	const defaults = (): RecordFilters => ({ preset: report ? 'all' : 'today', from: today().slice(0, 7) + '-01', through: today(), exact: today(), search: '', status: 'all', source: 'all' });
	let result = $state<Result>(); let filters = $state<RecordFilters>(defaults()); let page = $state(1);
	let loading = $state(true); let issue = $state(''); let request = 0; let detail = $state<StaffBooking>();
	const money = (cents?: number | null) => cents == null ? '—' : new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' }).format(cents / 100);
	const visitTime = (booking: StaffBooking) => booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00');
	const rows = $derived<ReportRow[]>((result?.records ?? []).map((booking) => ({
		id: booking.id, ref: booking.reference ?? booking.id, name: booking.customer_name, date: fmtDate(booking.visit_date, { month: 'short', day: 'numeric', year: 'numeric' }),
		time: visitTime(booking), services: servicesLine('', booking.services.length), status: booking.status,
		price: booking.status === 'done' ? money(booking.final_price_centavos) : '—'
	})));
	const notes = $derived(['Booking counts use the scheduled date. Completed service value uses the Philippine completion date.',
		...(result?.metrics.completedWithoutValue ? [`${result.metrics.completedWithoutValue} completed services have no final price and are excluded from income.`] : [])]);
	function range() {
		const { preset, from, through, exact } = filters;
		if (preset === 'all') return { from: '', through: '' };
		if (preset === 'date') return { from: exact, through: exact };
		if (preset === 'custom') return { from, through };
		return { from: preset === 'week' ? addDays(today(), -6) : preset === 'month' ? today().slice(0, 7) + '-01' : today(), through: today() };
	}
	async function load(next = 1) {
		// Invalid dates: drop any load still in flight so its old-filter answer is ignored.
		if (rangeIssue(filters)) { request++; loading = false; return; }
		const id = ++request; loading = true; issue = '';
		try {
			const response = await fetch(resolve('/api/staff/records'), { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...range(), search: filters.search, status: filters.status, source: filters.source, page: next, report }) });
			const data = await response.json(); if (id !== request) return;
			if (!response.ok) throw new Error(data.message ?? 'Booking records are unavailable.'); result = data; page = next;
		} catch (failure) { if (id === request) issue = failure instanceof Error ? failure.message : 'Booking records are unavailable.'; }
		finally { if (id === request) loading = false; }
	}
	function reset() { filters = defaults(); void load(); }
	onMount(() => { void load(); });
</script>
<div class="stack records">
	<PageHeader title={report ? 'Booking reports' : 'Booking history'} subtitle={report ? 'Review booking records and completed service value.' : 'Track bookings by appointment date.'} timezone />
	{#if !report && result && !issue && !rangeIssue(filters)}<StatusTiles selected={filters.status} onpick={(value) => { filters.status = value; void load(); }} tiles={[{ value: 'all', label: 'All bookings', count: result.metrics.total }, { value: 'pending', label: statusLabels.pending, count: result.metrics.pending }, { value: 'confirmed', label: statusLabels.confirmed, count: result.metrics.booked }, { value: 'done', label: statusLabels.done, count: result.metrics.completed }, { value: 'cancelled', label: statusLabels.cancelled, count: result.metrics.cancelled }]} />{/if}
	<div class="card"><RecordFilterBar bind:filters periods={report ? periods.filter((item) => item.value !== 'date') : periods} showStatus={report} onchange={() => load()} onreset={reset} /></div>
	{#if loading && !result}<p role="status">Loading booking records…</p>{/if}
	{#if issue}<div role="alert" class="stack"><p class="error">{issue}</p><div><button class="btn sm ghost" onclick={() => load(page)}>Try again</button></div></div>{/if}
	<!-- Never show the previous period's numbers next to filters they don't match (invalid dates or a failed load). -->
	{#if result && !issue && !rangeIssue(filters)}
		<div class="stack results" aria-busy={loading}>
			{#if report}<ReportSummary income={result.canViewIncome ? money(result.metrics.completedValueCentavos) : null} {notes} items={[['Bookings in period', result.metrics.total], ['Completed services', result.metrics.completed], ['Pending and booked', result.metrics.pending + result.metrics.booked], ['Walk-in bookings', result.metrics.walkIns], ['Cancelled bookings', result.metrics.cancelled]]} />{/if}
			<section class="stack" aria-labelledby="records-heading">
				<div class="row between"><h2 id="records-heading">{report ? 'Booking records' : 'Bookings'}</h2><p class="small muted" role="status">{result.total} {result.total === 1 ? 'record' : 'records'} · Newest first</p></div>
				{#if !result.records.length}<RecordsEmpty title="No bookings found" text="Try another date, status or search to find your bookings." action="Reset filters" onaction={reset} />
				{:else if report}<ReportList {rows} showPrice={result.canViewIncome} onDetails={(id) => detail = result?.records.find((item) => item.id === id)} />
				{:else}<div class="stack">{#each result.records as booking (booking.id)}<article class="card"><ServerStaffBookingCard {booking} when={fmtDate(booking.visit_date, { month: 'short', day: 'numeric' }) + ', ' + visitTime(booking)} onDetails={() => detail = booking} /></article>{/each}</div>{/if}
				<Pager {page} pages={result.pages} label="Booking records" onchange={(next) => load(next)} />
			</section>
		</div>
	{/if}
	<DetailsSheet title={detail ? 'Details for ' + detail.customer_name : 'Booking details'} open={Boolean(detail)} onclose={() => detail = undefined}>{#if detail}<ServerBookingDetails booking={detail} />{/if}</DetailsSheet>
</div>

<style>
	.records { min-width: 0; }
	.results[aria-busy='true'] { opacity: .6; }
	h2 { font-size: 1.35rem; }
	.between { justify-content: space-between; }
</style>
