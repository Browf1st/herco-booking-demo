<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { addDays, fmtDate, fmtSlot, today } from '../shared/dates';
	import BookMenu from '../shared/BookMenu.svelte';
	import DetailsSheet from '../shared/DetailsSheet.svelte';
	import PageHeader from '../shared/PageHeader.svelte';
	import Pager from '../shared/Pager.svelte';
	import RecordFilterBar from '../shared/RecordFilterBar.svelte';
	import RecordsEmpty from '../shared/RecordsEmpty.svelte';
	import ReportDetails, { type Detail } from '../shared/ReportDetails.svelte';
	import ReportSummary from '../shared/ReportSummary.svelte';
	import ReportTable from '../shared/ReportTable.svelte';
	import StatusTiles from '../shared/StatusTiles.svelte';
	import { rangeIssue, servicesLine, statusLabels, type RecordFilters } from '../shared/records-ui';
	import { manilaStamp, reportPrice, type ReportRow, type ReportSort } from '../shared/report-ui';
	import { parseWorkspaceAccess, type WorkspaceAccess } from '../shared/workspace-navigation';
	import ServerBookingDetails from './ServerBookingDetails.svelte';
	import ServerReportActions from './ServerReportActions.svelte';
	import ServerStaffBookingCard from './ServerStaffBookingCard.svelte';
	import type { StaffBooking } from './server-booking-types';
	let { report = false }: { report?: boolean } = $props();
	type Result = { records: StaffBooking[]; metrics: { total: number; pending: number; booked: number; completed: number; cancelled: number; walkIns: number; completedValueCentavos?: number | null; completedWithoutValue?: number }; total: number; pages: number; canViewIncome: boolean; sort?: ReportSort };
	const periods = [{ value: 'all', label: 'All dates' }, { value: 'today', label: 'Today' }, { value: 'week', label: 'Last 7 days' }, { value: 'month', label: 'This month' }, { value: 'date', label: 'Specific date' }, { value: 'custom', label: 'Custom range' }];
	const defaults = (): RecordFilters => ({ preset: report ? 'all' : 'today', from: today().slice(0, 7) + '-01', through: today(), exact: today(), search: '', status: 'all', source: 'all' });
	let result = $state<Result>(); let filters = $state<RecordFilters>(defaults()); let page = $state(1);
	// The sort the staff member asked for. The server sorts all records; `result.sort` is the sort that really ran.
	let sort = $state<ReportSort>('date');
	let loading = $state(true); let issue = $state(''); let request = 0; let detail = $state<StaffBooking>();
	// Reports only: what this staff member may do (for the Book menu and the popup buttons). The server still checks every action.
	let access = $state<WorkspaceAccess | null>(null);
	const money = (cents?: number | null) => cents == null ? '—' : new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' }).format(cents / 100);
	const visitTime = (booking: StaffBooking) => booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00');
	const isWalkIn = (booking: StaffBooking) => booking.source === 'walk-in' || booking.visit_hour === null;
	const refOf = (booking: StaffBooking) => booking.reference ?? booking.id;
	function toRow(booking: StaffBooking, showMoney: boolean): ReportRow {
		// The booking-time estimate comes from the server. It is null when unknown or without the income permission.
		const estimate = booking.original_total_centavos ?? undefined;
		const price = reportPrice(booking.status, booking.final_price_centavos == null ? null : money(booking.final_price_centavos), estimate === undefined ? null : money(estimate));
		return {
			id: booking.id, ref: refOf(booking), name: booking.customer_name, bike: booking.bike, walkIn: isWalkIn(booking), phone: booking.customer_phone,
			date: fmtDate(booking.visit_date, { month: 'short', day: 'numeric', year: 'numeric' }), time: booking.visit_hour === null ? '' : visitTime(booking),
			services: servicesLine('', booking.services.length), status: booking.status,
			price: showMoney ? price.text : undefined, priceKind: price.kind,
			priceValue: price.kind === 'final' ? booking.final_price_centavos ?? undefined : price.kind === 'estimate' ? estimate : undefined
		};
	}
	const rows = $derived<ReportRow[]>((result?.records ?? []).map((booking) => toRow(booking, Boolean(result?.canViewIncome))));
	const notes = $derived(['Booking counts use the scheduled date. Completed service value uses the Philippine completion date.',
		...(result?.metrics.completedWithoutValue ? [`${result.metrics.completedWithoutValue} completed services have no final price and are excluded from income.`] : [])]);
	// Booking references are listed only when the whole period fits on this page and the list matches the count.
	const refsFor = (list: StaffBooking[], count: number) => result && result.pages === 1 && list.length === count ? list.map(refOf) : undefined;
	const refs = $derived({
		completed: refsFor((result?.records ?? []).filter((booking) => booking.status === 'done'), result?.metrics.completed ?? -1),
		walkIns: refsFor((result?.records ?? []).filter(isWalkIn), result?.metrics.walkIns ?? -1),
		cancelled: refsFor((result?.records ?? []).filter((booking) => booking.status === 'cancelled'), result?.metrics.cancelled ?? -1)
	});
	const canBook = $derived(Boolean(access?.pages.includes('Bookings') && access.actions.includes('createBooking')));
	const bookLinks = [{ label: 'Walk-in', href: resolve('/manual-booking?walk-in=1') }, { label: 'Online', href: resolve('/manual-booking') }];
	function detailOf(booking: StaffBooking, showMoney: boolean): Detail {
	return {
		name: booking.customer_name, ref: refOf(booking), status: booking.status, walkIn: isWalkIn(booking), bike: booking.plate ? booking.bike + ' · Plate ' + booking.plate : booking.bike,
		lines: booking.current_services?.length
			? booking.current_services.map((line) => ({ label: line.label, price: showMoney ? money(line.price_centavos) : undefined, parts: line.details?.map((part) => ({ label: part.label, price: showMoney ? money(part.price_centavos) : undefined })) }))
			: booking.services.map((label) => ({ label })),
		total: showMoney && booking.total_centavos != null ? money(booking.total_centavos) : undefined,
		phone: booking.customer_phone || undefined, email: booking.customer_email,
		visit: fmtDate(booking.visit_date) + ' · ' + visitTime(booking), booked: manilaStamp(booking.created_at),
		approved: manilaStamp(booking.approved_at), completed: manilaStamp(booking.completed_at)
	};
	}
	const popup = $derived(detail ? detailOf(detail, Boolean(result?.canViewIncome)) : undefined);
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
			const response = await fetch(resolve('/api/staff/records'), { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...range(), search: filters.search, status: filters.status, source: filters.source, page: next, report, sort }) });
			const data = await response.json(); if (id !== request) return;
			if (!response.ok) throw new Error(data.message ?? 'Booking records are unavailable.'); result = data; page = next;
		} catch (failure) { if (id === request) issue = failure instanceof Error ? failure.message : 'Booking records are unavailable.'; }
		finally { if (id === request) loading = false; }
	}
	async function loadAccess() {
		try {
			const response = await fetch(resolve('/api/staff/workspace'), { headers: { accept: 'application/json' } });
			if (response.ok) access = parseWorkspaceAccess(await response.json());
		} catch { access = null; }
	}
	function reset() { filters = defaults(); void load(); }
	function savedAction() { detail = undefined; void load(page); }
	onMount(() => { void load(); if (report) void loadAccess(); });
</script>
<div class="stack records">
	{#if report}
		<PageHeader title="Booking reports" badge="Workshop view" subtitle="Review booking records and completed service value." timezone>{#if canBook}<BookMenu links={bookLinks} />{/if}</PageHeader>
	{:else}
		<PageHeader title="Booking history" subtitle="Track bookings by appointment date." timezone />
	{/if}
	{#if !report && result && !issue && !rangeIssue(filters)}<StatusTiles selected={filters.status} onpick={(value) => { filters.status = value; void load(); }} tiles={[{ value: 'all', label: 'All bookings', count: result.metrics.total }, { value: 'pending', label: statusLabels.pending, count: result.metrics.pending }, { value: 'confirmed', label: statusLabels.confirmed, count: result.metrics.booked }, { value: 'done', label: statusLabels.done, count: result.metrics.completed }, { value: 'cancelled', label: statusLabels.cancelled, count: result.metrics.cancelled }]} />{/if}
	<div class="card"><RecordFilterBar bind:filters periods={report ? periods.filter((item) => item.value !== 'date') : periods} showStatus={report} onchange={() => load()} onreset={reset} /></div>
	{#if loading && !result}<p role="status">Loading booking records…</p>{/if}
	{#if issue}<div role="alert" class="stack"><p class="error">{issue}</p><div><button class="btn sm ghost" onclick={() => load(page)}>Try again</button></div></div>{/if}
	<!-- Never show the previous period's numbers next to filters they don't match (invalid dates or a failed load). -->
	{#if result && !issue && !rangeIssue(filters)}
		<div class="stack results" aria-busy={loading}>
			{#if report}<ReportSummary income={result.canViewIncome ? money(result.metrics.completedValueCentavos) : null} {notes} {refs}
				counts={{ total: result.metrics.total, completed: result.metrics.completed, pending: result.metrics.pending, booked: result.metrics.booked, walkIns: result.metrics.walkIns, cancelled: result.metrics.cancelled }} />{/if}
			{#if !result.records.length}<RecordsEmpty title="No bookings found" text="Try another date, status or search to find your bookings." action="Reset filters" onaction={reset} />
			{:else if report}<ReportTable {rows} total={result.total} {page} pages={result.pages} showPrice={result.canViewIncome} selectedId={detail?.id ?? ''} busy={loading} sort={result.sort ?? sort} sortAll onsort={(next) => { sort = next; void load(); }} onDetails={(id) => detail = result?.records.find((item) => item.id === id)} onpage={(next) => load(next)} />
			{:else}
				<section class="stack" aria-labelledby="records-heading">
					<div class="row between"><h2 id="records-heading">Bookings</h2><p class="small muted" role="status">{result.total} {result.total === 1 ? 'record' : 'records'} · Newest first</p></div>
					<div class="stack">{#each result.records as booking (booking.id)}<article class="card"><ServerStaffBookingCard {booking} when={fmtDate(booking.visit_date, { month: 'short', day: 'numeric' }) + ', ' + visitTime(booking)} onDetails={() => detail = booking} /></article>{/each}</div>
					<Pager {page} pages={result.pages} label="Booking records" onchange={(next) => load(next)} />
				</section>
			{/if}
		</div>
	{/if}
	{#if report}
		{#if popup && detail}<ReportDetails detail={popup} onclose={() => detail = undefined}>{#snippet actions()}{#if access}<ServerReportActions booking={detail!} actions={access.actions} onsaved={savedAction} />{/if}{/snippet}</ReportDetails>{/if}
	{:else}
		<DetailsSheet title={detail ? 'Details for ' + detail.customer_name : 'Booking details'} open={Boolean(detail)} onclose={() => detail = undefined}>{#if detail}<ServerBookingDetails booking={detail} />{/if}</DetailsSheet>
	{/if}
</div>

<style>
	.records { min-width: 0; }
	.results[aria-busy='true'] { opacity: .6; }
	h2 { font-size: 1.35rem; }
	.between { justify-content: space-between; }
</style>
