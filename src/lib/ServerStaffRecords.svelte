<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { addDays, fmtDate, fmtSlot, today } from './dates';
	import ActionIcon from './ActionIcon.svelte';
	import ServerStaffBookingCard from './ServerStaffBookingCard.svelte';
	import type { StaffBooking } from './server-booking-types';
	let { report = false }: { report?: boolean } = $props();
	type Result = { records: StaffBooking[]; metrics: { total: number; pending: number; booked: number; completed: number; cancelled: number; walkIns: number; completedValueCentavos?: number | null; completedWithoutValue?: number }; total: number; pages: number; canViewIncome: boolean };
	let result = $state<Result>(); let preset = $state(''); let from = $state(today().slice(0, 7) + '-01');
	let through = $state(today()); let exact = $state(today()); let search = $state(''); let status = $state('all');
	let source = $state('all'); let page = $state(1); let loading = $state(true); let issue = $state(''); let request = 0;
	const labels = { pending: 'Pending', confirmed: 'Booked', done: 'Completed', cancelled: 'Cancelled' };
	const money = (cents?: number | null) => cents == null ? '—' : new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' }).format(cents / 100);
	const periods = [{ value: 'all', label: 'All dates' }, { value: 'today', label: 'Today' }, { value: 'week', label: 'Last 7 days' }, { value: 'month', label: 'This month' }, { value: 'date', label: 'Specific date' }, { value: 'custom', label: 'Custom range' }];
	function range() {
		if (preset === 'all') return { from: '', through: '' };
		if (preset === 'date') return { from: exact, through: exact };
		if (preset === 'custom') return { from, through };
		return { from: preset === 'week' ? addDays(today(), -6) : preset === 'month' ? today().slice(0, 7) + '-01' : today(), through: today() };
	}
	async function load(next = 1) {
		const id = ++request; loading = true; issue = '';
		try {
			const response = await fetch(resolve('/api/staff/records'), { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...range(), search, status, source, page: next, report }) });
			const data = await response.json(); if (id !== request) return;
			if (!response.ok) throw new Error(data.message ?? 'Booking records are unavailable.'); result = data; page = next;
		} catch (failure) { if (id === request) issue = failure instanceof Error ? failure.message : 'Booking records are unavailable.'; }
		finally { if (id === request) loading = false; }
	}
	function reset() { preset = report ? 'all' : 'today'; search = ''; status = source = 'all'; from = today().slice(0, 7) + '-01'; through = exact = today(); void load(); }
	onMount(() => { preset = report ? 'all' : 'today'; void load(); });
</script>
<div class="report-layout history-workspace staff-records-parity">
	<div class="history-heading"><div><h2>{report ? 'Booking reports' : 'Booking history'}</h2><p class="muted">{report ? 'Review booking records and completed service value.' : 'Track bookings by appointment date.'}</p></div><span class="history-timezone"><ActionIcon name="clock" />Philippine time</span></div>
	{#if !report && result}<div class="booking-metrics">{#each [['all', 'All bookings', result.metrics.total], ['pending', 'Pending', result.metrics.pending], ['confirmed', 'Booked', result.metrics.booked], ['done', 'Completed', result.metrics.completed], ['cancelled', 'Cancelled', result.metrics.cancelled]] as [value, label, count]}<button class="card booking-metric" data-status={value} aria-pressed={status === value} onclick={() => { status = String(value); void load(); }}><span class="metric-label"><span class="metric-dot"></span>{label}</span><span class="metric-value"><b>{count}</b>{#if status === value}<span class="metric-selected"><ActionIcon name="check" /></span>{/if}</span></button>{/each}</div>{/if}
	<form class="card stack history-filters report-panel" onsubmit={(event) => { event.preventDefault(); void load(); }}>
		<div class="row between filter-heading"><span><ActionIcon name="adjust" />Filter bookings</span><button type="button" class="history-reset" onclick={reset}><ActionIcon name="reset" />Reset filters</button></div>
		{#if report}<div class="report-period">{#each periods.filter(item => item.value !== 'date') as item}<button type="button" aria-pressed={preset === item.value} onclick={() => { preset = item.value; void load(); }}><ActionIcon name="calendar" />{item.label}</button>{/each}</div>{/if}
		<div class="history-filter-fields"><label class="history-search">Search bookings<input type="search" bind:value={search} placeholder="Name, reference, mobile, bike or plate" maxlength="254" /></label>{#if !report}<label>Date filter<select bind:value={preset} onchange={() => { void load(); }}>{#each periods as item}<option value={item.value}>{item.label}</option>{/each}</select></label>{/if}<label>Status<select bind:value={status} onchange={() => { void load(); }}><option value="all">All statuses</option>{#each Object.entries(labels) as [value, label]}<option {value}>{label}</option>{/each}</select></label><label>Booking source<select bind:value={source} onchange={() => { void load(); }}><option value="all">All sources</option><option value="online">Online</option><option value="walk-in">Walk-in</option></select></label></div>
		{#if preset === 'date'}<label>Appointment date<input type="date" bind:value={exact} required /></label>{:else if preset === 'custom'}<div class="history-date-fields"><label>From<input type="date" bind:value={from} required /></label><label>To<input type="date" bind:value={through} min={from} required /></label></div>{/if}
		<div><button class="btn sm ghost" disabled={loading}>Apply filters</button></div>
	</form>
	{#if loading}<p role="status">Loading booking records…</p>{/if}{#if issue}<p role="alert">{issue}</p><button class="btn sm ghost" onclick={() => load(page)}>Try again</button>{/if}
	{#if result && !loading}
		{#if report}<dl class="report-metrics">{#if result.canViewIncome}<div class="card" data-metric="income"><dt>Total income from completed services</dt><dd>{money(result.metrics.completedValueCentavos)}</dd></div>{/if}{#each [['Bookings in period', result.metrics.total], ['Completed services', result.metrics.completed], ['Pending and booked', result.metrics.pending + result.metrics.booked], ['Walk-in bookings', result.metrics.walkIns], ['Cancelled bookings', result.metrics.cancelled]] as [label, value]}<div class="card"><dt>{label}</dt><dd>{value}</dd></div>{/each}</dl>{/if}
		<section class={report ? 'card stack report-panel' : 'stack'} aria-labelledby="records-heading"><div class="row between"><h3 id="records-heading">{report ? 'Booking records' : 'Bookings'}</h3><p class="small muted">{result.total} {result.total === 1 ? 'record' : 'records'} · Newest first</p></div>
		{#if report}<p class="small muted">Booking counts use the scheduled date. Completed service value uses the Philippine completion date.</p>{#if result.metrics.completedWithoutValue}<p class="small muted">{result.metrics.completedWithoutValue} completed services have no final price and are excluded from income.</p>{/if}
			<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
			<div class="report-table" role="region" aria-label="Booking records" tabindex="0"><table><thead><tr><th>Booking</th><th>Service</th><th>Scheduled</th><th>Completed</th><th>Status</th><th>Source</th>{#if result.canViewIncome}<th class="report-price">Final price</th>{/if}</tr></thead><tbody>{#each result.records as booking (booking.id)}<tr><td><strong>{booking.customer_name}</strong><div class="small muted">{booking.reference ?? booking.id}</div></td><td>{booking.services.join(' · ')}<div class="small muted">{booking.bike}</div><ServerStaffBookingCard {booking} /></td><td>{fmtDate(booking.visit_date)}<div class="small muted">{booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00')}</div></td><td>{booking.completed_at ? new Date(booking.completed_at).toLocaleDateString('en-PH', { timeZone: 'Asia/Manila' }) : '—'}</td><td><span class="badge" data-status={booking.status === 'confirmed' ? 'booked' : booking.status}>{labels[booking.status]}</span></td><td>{booking.source === 'walk-in' ? 'Walk-in' : 'Online'}</td>{#if result.canViewIncome}<td class="report-price">{booking.status === 'done' ? money(booking.final_price_centavos) : '—'}</td>{/if}</tr>{/each}</tbody></table></div>
		{:else}<div class="history-records">{#each result.records as booking (booking.id)}<article class="card booking-entry"><ServerStaffBookingCard {booking}>{#snippet heading()}<div class="record-header"><div class="record-heading"><strong>{booking.customer_name}</strong><span class="record-reference">{booking.reference ?? booking.id}<span class="record-bike"> · {booking.bike}</span></span></div><div class="record-appointment"><span><ActionIcon name="calendar" />{fmtDate(booking.visit_date)}</span><span class="record-time">{booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00')}</span></div><div class="record-status"><span class="badge" data-status={booking.status === 'confirmed' ? 'booked' : booking.status}>{labels[booking.status]}</span></div></div>{/snippet}</ServerStaffBookingCard></article>{/each}</div>{/if}
		{#if !result.records.length}<div class="card history-empty"><span class="empty-icon"><ActionIcon name="calendar" /></span><h3>No bookings found</h3><p class="muted">Try another date, status or search to find your bookings.</p><button class="btn sm ghost" onclick={reset}>Reset filters</button></div>{/if}
		{#if result.pages > 1}<nav class="row history-pagination" aria-label="Booking records pagination"><button class="btn sm ghost" disabled={page <= 1} onclick={() => load(page - 1)}><ActionIcon name="left" />Previous</button><span class="small muted">Page {page} of {result.pages}</span><button class="btn sm ghost" disabled={page >= result.pages} onclick={() => load(page + 1)}><ActionIcon name="right" />Next</button></nav>{/if}
		</section>
	{/if}
</div>

<style>

 :global(.staff-records-parity .report-layout) { display: grid; gap: 1rem; min-width: 0; }
 :global(.staff-records-parity .report-panel) { gap: .85rem; min-width: 0; }
 :global(.staff-records-parity .report-toolbar) { align-items: center; justify-content: space-between; border-bottom: 1px solid var(--line); padding-bottom: .7rem; }
 :global(.staff-records-parity .report-actions) { align-items: center; gap: .5rem; }
 :global(.staff-records-parity .report-period) { display: flex; flex-wrap: wrap; gap: .15rem; padding: .2rem; background: var(--panel-2); border: 1px solid var(--line); border-radius: .35rem; }
 :global(.staff-records-parity .report-period button), :global(.staff-records-parity .report-reset) { font: inherit; font-size: .75rem; font-weight: 750; text-transform: uppercase; padding: .35rem .55rem; border: 1px solid transparent; border-radius: .25rem; cursor: pointer; color: var(--text); background: transparent; }
 :global(.staff-records-parity .report-period button[aria-pressed="true"]) { color: var(--accent-ink); background: var(--accent-fill); }
 :global(.staff-records-parity .report-period button:hover[aria-pressed="false"]), :global(.staff-records-parity .report-reset:hover) { background: var(--panel-2); border-color: var(--line); }
 :global(.staff-records-parity .report-reset) { color: var(--accent); border-color: var(--line); }
 :global(.staff-records-parity .report-filters) { display: grid; grid-template-columns: 2fr 1fr 1fr; gap: .75rem; }
 :global(.staff-records-parity .report-filters input), :global(.staff-records-parity .report-filters select) { padding-block: .45rem; }
 :global(.staff-records-parity .report-metrics) { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .75rem; margin: 0; }
 :global(.staff-records-parity .report-metrics > div) { display: flex; flex-direction: column; justify-content: space-between; padding: .85rem; }
 :global(.staff-records-parity .report-metrics dt), :global(.staff-records-parity th) { font-size: .75rem; font-weight: 700; letter-spacing: .04em; text-transform: uppercase; }
 :global(.staff-records-parity .report-metrics dd) { margin: .4rem 0 0; font-size: 1.5rem; font-weight: 750; font-variant-numeric: tabular-nums; }
 :global(.staff-records-parity .report-metrics [data-metric="completed"] dd), :global(.staff-records-parity .report-metrics [data-metric="income"] dd) { color: var(--ok); }
 :global(.staff-records-parity .report-metrics [data-metric="cancelled"] dd) { color: var(--accent); }
 :global(.staff-records-parity .report-table) { overflow-x: auto; border: 1px solid var(--line); border-radius: .35rem; }
 :global(.staff-records-parity table) { width: 100%; min-width: 920px; border-collapse: collapse; }
 :global(.staff-records-parity th), :global(.staff-records-parity td) { padding: .6rem .7rem; text-align: left; vertical-align: top; border-bottom: 1px solid var(--line); }
 :global(.staff-records-parity th), :global(.staff-records-parity tbody tr:nth-child(even)) { background: var(--panel-2); }
 :global(.staff-records-parity tbody tr:last-child td) { border-bottom: 0; }
 :global(.staff-records-parity .report-price) { text-align: right; font-variant-numeric: tabular-nums; }
 :global(.staff-records-parity .report-visit), :global(.staff-records-parity td:nth-child(n+4)) { white-space: nowrap; }
 @media (max-width: 850px) { :global(.staff-records-parity .report-metrics) { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
 @media (max-width: 570px) { :global(.staff-records-parity .report-filters) { grid-template-columns: minmax(0, 1fr); } }


	:global(.staff-records-parity .customer-total) { display: grid; gap: .25rem; }
	:global(.staff-records-parity .customer-total b) { font-size: 1.6rem; }
	:global(.staff-records-parity .customer-record) { padding: 0; overflow-wrap: anywhere; }
	:global(.staff-records-parity .customer-record > summary) { padding: .65rem .9rem; cursor: pointer; }
	:global(.staff-records-parity .customer-record[open] > summary) { background: var(--panel-2); border-radius: 6px 6px 0 0; }
	:global(.staff-records-parity .customer-record-meta) { display: inline-flex; flex-wrap: wrap; align-items: center; gap: .4rem; margin-inline-start: .55rem; color: var(--muted); font-size: .85rem; }
	:global(.staff-records-parity .customer-record .customer-profile) { padding: .9rem; }
	:global(.staff-records-parity .customer-details) { background: var(--bg); border: 1px solid var(--line); padding: .7rem; border-radius: 4px; }
	:global(.staff-records-parity .inventory-metrics.redemption-metrics > div) {
		background: var(--panel);
		border: 1px solid var(--status-border);
	}
	:global(.staff-records-parity .redemption-metrics [data-redemption-status="pending"]) {
		--status-border: var(--warn-line);
	}
	:global(.staff-records-parity .redemption-metrics [data-redemption-status="approved"]) {
		--status-border: var(--info-line);
	}
	:global(.staff-records-parity .redemption-metrics [data-redemption-status="claimed"]) {
		--status-border: var(--ok-line);
	}
	:global(.staff-records-parity .inventory-heading) { justify-content: space-between; }
	:global(.staff-records-parity .inventory-option-link) { border: 0; background: transparent; color: var(--accent); font: inherit; font-size: .85rem; font-weight: 700; cursor: pointer; padding: .25rem; }
	:global(.staff-records-parity .inventory-option-link:hover) { text-decoration: underline; }
	:global(.staff-records-parity .inventory-actions), :global(.staff-records-parity .stock-row-actions) { gap: .35rem; }
	:global(.staff-records-parity .inventory-actions .btn), :global(.staff-records-parity .stock-row-actions .btn), :global(.staff-records-parity .inventory-form .btn) {
		clip-path: none; border-radius: .25rem; font-style: normal;
	}
	:global(.staff-records-parity .stock-panel) { min-width: 0; }
	:global(.staff-records-parity .inventory-metrics.stock-metrics > div) { align-content: start; background: var(--panel); border: 1px solid var(--line); }
	:global(.staff-records-parity .stock-metrics > div:nth-child(2)) { border-color: var(--ok-line); }
	:global(.staff-records-parity .stock-metrics > div:nth-child(3)) { border-color: var(--warn-line); }
	:global(.staff-records-parity .stock-metrics dd) { font-variant-numeric: tabular-nums; }
	:global(.staff-records-parity .stock-table) { overflow-x: auto; border: 1px solid var(--line); border-radius: .35rem; }
	:global(.staff-records-parity .stock-table table) { width: 100%; min-width: 850px; border-collapse: collapse; font-size: .9rem; }
	:global(.staff-records-parity .stock-table th), :global(.staff-records-parity .stock-table td) { padding: .55rem .65rem; text-align: left; border-bottom: 1px solid var(--line); }
	:global(.staff-records-parity .stock-table thead th) { background: var(--panel-2); text-transform: uppercase; font-size: .75rem; letter-spacing: .03em; }
	:global(.staff-records-parity .stock-table tbody th) { font-weight: 400; }
	:global(.staff-records-parity .stock-table tr:last-child td), :global(.staff-records-parity .stock-table tbody tr:last-child th) { border-bottom: 0; }
	:global(.staff-records-parity .stock-row-actions) { justify-content: flex-end; flex-wrap: nowrap; }
	:global(.staff-records-parity .stock-table th:last-child) { text-align: right; }
	:global(.staff-records-parity .stock-gauge progress) { display: block; width: 100%; height: .5rem; }
	:global(.staff-records-parity .stock-gauge span) { white-space: nowrap; }
	:global(.staff-records-parity .stock-panel), :global(.staff-records-parity .stock-table) {
		--stock-border: light-dark(#eddcd7, #465467);
		--stock-blue: light-dark(#edf3ff, #242d3a);
		--stock-muted: light-dark(#765851, #b9c4d4);
		border-color: var(--stock-border);
	}
	:global(.staff-records-parity .stock-panel input), :global(.staff-records-parity .stock-panel select) { background: var(--panel); border-color: var(--stock-border); color: var(--text); }
	:global(.staff-records-parity .stock-table) { background: var(--panel); color: var(--text); }
	:global(.staff-records-parity .stock-table th), :global(.staff-records-parity .stock-table td) { border-color: light-dark(#f0e7e4, #343e4c); }
	:global(.staff-records-parity .stock-table thead th) { background: var(--panel); color: var(--stock-muted); }
	:global(.staff-records-parity .stock-table .muted), :global(.staff-records-parity .stock-table td:nth-child(2)) { color: var(--stock-muted); }
	:global(.staff-records-parity .stock-table .low-stock) { background: color-mix(in srgb, var(--warn-bg) 38%, var(--panel)); }
	:global(.staff-records-parity .stock-table .low-stock .muted) { color: var(--warn); }
	:global(.staff-records-parity .stock-table .badge) { display: inline-block; white-space: nowrap; border: 1px solid; border-radius: .18rem; padding: .2rem .4rem; font-family: inherit; font-size: .72rem; font-weight: 700; line-height: 1.2; letter-spacing: .025em; }
	:global(.staff-records-parity .stock-table .badge[data-status="done"]) { border-color: var(--ok-line); }
	:global(.staff-records-parity .stock-table .badge[data-status="pending"]) { border-color: var(--warn-line); }
	:global(.staff-records-parity .stock-table .badge[data-status="cancelled"]) { border-color: var(--bad-line); }
	:global(.staff-records-parity .stock-row-actions .btn) { background: var(--stock-blue); color: var(--text); border: 1px solid var(--stock-border); white-space: nowrap; padding: .35rem .55rem; font-family: inherit; font-size: .75rem; font-weight: 700; line-height: 1.2; }
	:global(.staff-records-parity .stock-row-actions .btn:last-child) { background: var(--panel); color: var(--stock-muted); }
	:global(.staff-records-parity .stock-row-actions .btn:last-child:hover) { background: var(--stock-blue); }
	:global(.staff-records-parity .stock-row-actions .stock-in) { background: var(--ok-bg); color: var(--ok); border-color: var(--ok-line); }
	:global(.staff-records-parity .stock-row-actions .stock-out) { background: var(--bad-bg); color: var(--bad); border-color: var(--bad-line); }
	:global(.staff-records-parity .stock-row-actions .stock-in:hover:not(:disabled)) { background: color-mix(in srgb, var(--ok-bg) 85%, var(--ok)); }
	:global(.staff-records-parity .stock-row-actions .stock-out:hover:not(:disabled)) { background: color-mix(in srgb, var(--bad-bg) 85%, var(--bad)); }
	:global(.staff-records-parity .stock-gauge progress) {
		--gauge-track: var(--info-bg);
		--gauge-fill: light-dark(#00936b, #61c99d);
		appearance: none; border: 0; border-radius: 1rem; background: var(--gauge-track); overflow: hidden;
	}
	:global(.staff-records-parity .stock-gauge progress[data-health="low"]) { --gauge-track: var(--warn-bg); --gauge-fill: light-dark(#d78300, #f0b85f); }
	:global(.staff-records-parity .stock-gauge progress::-webkit-progress-bar) { background: var(--gauge-track); border-radius: 1rem; }
	:global(.staff-records-parity .stock-gauge progress::-webkit-progress-value) { background: var(--gauge-fill); border-radius: 1rem; }
	:global(.staff-records-parity .stock-gauge progress::-moz-progress-bar) { background: var(--gauge-fill); border-radius: 1rem; }
	:global(.staff-records-parity .stock-history label) { max-width: 20rem; margin-block: .65rem; }
	:global(.staff-records-parity dialog.inventory-form) { width: min(860px, calc(100vw - 32px)); }
	:global(.staff-records-parity .inventory-fields) { min-inline-size: 0; margin: 0; padding: .8rem; border: 1px solid var(--line); border-radius: .4rem; }
	:global(.staff-records-parity .inventory-fields legend) { padding-inline: .35rem; font-weight: 700; }
	:global(.staff-records-parity .stock-level-fields label) { background: var(--panel-2); padding: .6rem; border-radius: .3rem; }
	:global(.staff-records-parity .stock-level-fields label:nth-child(2)) { border-inline-start: 3px solid var(--accent); }
	:global(.staff-records-parity .inventory-form-footer) { justify-content: space-between; border-top: 1px solid var(--line); padding-top: .75rem; }
	:global(.staff-records-parity .redemption-row) { border-top: 1px solid var(--line); padding-block: .75rem; }
	:global(.staff-records-parity .redemption-row[open] summary) { margin-bottom: .75rem; }
	:global(.staff-records-parity .redemption-summary) { display: inline-flex; flex-wrap: wrap; align-items: center; gap: .35rem .9rem; vertical-align: middle; }
	:global(.staff-records-parity .redemption-meta) { display: block; }
	:global(.staff-records-parity .fan-results) { display: grid; gap: .4rem; list-style: none; padding: 0; margin: 0; max-height: 16rem; overflow: auto; }
	:global(.staff-records-parity .fan-results button) { display: grid; width: 100%; overflow-wrap: anywhere; }
	:global(.staff-records-parity .rewards-heading), :global(.staff-records-parity .reward-line) { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: .6rem; align-items: baseline; }
	:global(.staff-records-parity .rewards-heading) { align-items: center; }
	:global(.staff-records-parity .rewards-heading .btn), :global(.staff-records-parity .reward-points) { white-space: nowrap; }
	:global(.staff-records-parity .reward-points) { font-size: 1.2rem; text-align: right; }
	:global(.staff-records-parity .admin-points-layout) { display: grid; grid-template-columns: minmax(0, 2fr) minmax(0, 1fr); gap: 1rem; align-items: start; }
	:global(.staff-records-parity .rank-fan) { overflow-wrap: anywhere; }
	@media (max-width: 900px) { :global(.staff-records-parity .admin-points-layout) { grid-template-columns: minmax(0, 1fr); } }
	:global(.staff-records-parity .inventory-metrics) { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: .75rem; margin: 0; }
	:global(.staff-records-parity .inventory-metrics > div) { display: grid; gap: .35rem; padding: .75rem; border-radius: .35rem; background: var(--panel-2); }
	:global(.staff-records-parity .inventory-metrics dd) { margin: 0; font-size: 1.5rem; font-weight: 700; }
	:global(.staff-records-parity dialog) {
		width: min(560px, calc(100vw - 32px));
		max-height: calc(100dvh - 48px);
		padding: 24px;
		overflow-y: auto;
		border: 1px solid var(--line);
		border-radius: 12px;
		background: var(--panel);
		color: var(--text);
	}
	:global(.staff-records-parity dialog::backdrop) { background: rgb(0 0 0 / 75%); }
	:global(.staff-records-parity .dialog-heading) { justify-content: space-between; }
	:global(.staff-records-parity .close-dialog) { display: grid; place-items: center; width: 40px; height: 40px; border: 1px solid var(--line); border-radius: 50%; background: var(--panel-2); color: var(--text); font-size: 1.25rem; cursor: pointer; }
	:global(.staff-records-parity .customer-profile) { padding-top: 18px; }
	:global(.staff-records-parity .rank-row) { display: flex; flex-wrap: wrap; align-items: center; gap: 16px; padding-block: 18px; border-bottom: 1px solid var(--line); }
	:global(.staff-records-parity .rank-number) { font: italic 800 1.8rem var(--display); color: var(--muted); min-width: 40px; }
	:global(.staff-records-parity .podium) { color: var(--accent); }
	:global(.staff-records-parity .rank-fan) { display: grid; flex: 1 1 160px; gap: 4px; }
	:global(.staff-records-parity .rank-points) { font-size: 1.3rem; min-width: 95px; }
	:global(.staff-records-parity .rank-points span) { display: block; }
	:global(.staff-records-parity .history-workspace) { gap: 1.15rem; }
	:global(.staff-records-parity .history-heading) { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .65rem; padding-block: .4rem; }
	:global(.staff-records-parity .history-heading h2) { font-size: clamp(2rem, 4vw, 2.6rem); }
	:global(.staff-records-parity .history-heading p) { font-size: .85rem; margin-top: .45rem; }
	:global(.staff-records-parity .history-timezone) { display: inline-flex; align-items: center; gap: .4rem; color: var(--muted); font-size: .75rem; }
	:global(.staff-records-parity .booking-metrics) { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: .65rem; }
	:global(.staff-records-parity .booking-metric) { --metric-color: var(--text); display: grid; gap: .75rem; padding: .85rem; text-align: left; color: var(--text); cursor: pointer; font: inherit; border-color: color-mix(in srgb, var(--line) 65%, var(--panel)); border-radius: 8px; }
	:global(.staff-records-parity .metric-label) { display: flex; align-items: center; gap: .4rem; font-size: .78rem; font-weight: 600; }
	:global(.staff-records-parity .metric-dot) { width: .4rem; height: .4rem; flex: none; border-radius: 50%; background: var(--metric-color); }
	:global(.staff-records-parity .metric-value) { display: flex; align-items: center; justify-content: space-between; }
	:global(.staff-records-parity .booking-metric b) { font-size: 1.9rem; line-height: 1; font-weight: 700; font-variant-numeric: tabular-nums; }
	:global(.staff-records-parity .metric-selected) { display: grid; place-items: center; width: 1.3rem; height: 1.3rem; color: var(--accent); }
	:global(.staff-records-parity .booking-metric[data-status="pending"]) { --metric-color: light-dark(#d69b00, #f7cf82); }
	:global(.staff-records-parity .booking-metric[data-status="confirmed"]) { --metric-color: var(--accent); }
	:global(.staff-records-parity .booking-metric[data-status="done"]) { --metric-color: var(--ok); }
	:global(.staff-records-parity .booking-metric[data-status="cancelled"]) { --metric-color: var(--bad); }
	:global(.staff-records-parity .booking-metric:hover) { background: var(--panel-2); border-color: var(--muted); }
	:global(.staff-records-parity .booking-metric[aria-pressed="true"]) { border-color: var(--accent); background: color-mix(in srgb, var(--accent) 4%, var(--panel)); box-shadow: inset 0 0 0 1px var(--accent); }
	:global(.staff-records-parity .history-filters) { display: grid; gap: .85rem; border-radius: 8px; border-color: color-mix(in srgb, var(--line) 65%, var(--panel)); }
	:global(.staff-records-parity .filter-heading) { justify-content: space-between; font-size: .8rem; font-weight: 650; }
	:global(.staff-records-parity .filter-heading > span) { display: inline-flex; align-items: center; gap: .4rem; }
	:global(.staff-records-parity .history-reset) { min-height: 36px; padding: .25rem .4rem; border: 0; border-radius: 4px; color: var(--accent); background: transparent; font: inherit; cursor: pointer; }
	:global(.staff-records-parity .history-reset:hover) { background: var(--panel-2); }
	:global(.staff-records-parity .history-filter-fields) { display: grid; grid-template-columns: minmax(0, 2fr) repeat(3, minmax(0, 1fr)); gap: .8rem; }
	:global(.staff-records-parity .history-filters label) { font-size: .78rem; font-weight: 600; }
	:global(.staff-records-parity .history-filters input), :global(.staff-records-parity .history-filters select) { font-size: .85rem; font-weight: 400; background: var(--panel); border-radius: 6px; }
	:global(.staff-records-parity .history-date-fields) { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .8rem; border-top: 1px solid var(--line); padding-top: .85rem; }
	:global(.staff-records-parity .filter-hint) { font-size: .72rem; color: var(--muted); }
	:global(.staff-records-parity .history-results-heading) { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .4rem; padding-top: .4rem; }
	:global(.staff-records-parity .history-results-heading h3) { font-size: 1.35rem; }
	:global(.staff-records-parity .history-results-heading p) { font-size: .75rem; }
	:global(.staff-records-parity .history-records) { display: grid; gap: .55rem; }
	:global(.staff-records-parity .booking-entry) { padding: .85rem; }
	:global(.staff-records-parity .booking-record) { margin-block-start: .55rem; border-top: 1px solid var(--line); }
	:global(.staff-records-parity .booking-record > summary) { width: fit-content; padding: .35rem .35rem 0 0; color: var(--muted); font-size: .8rem; font-weight: 700; }
	:global(.staff-records-parity .booking-record:not([open]) .open-label), :global(.staff-records-parity .booking-record[open] .closed-label) { display: none; }
	:global(.staff-records-parity .record-header) { display: grid; grid-template-columns: minmax(0, 1fr) auto auto; align-items: start; gap: .5rem .95rem; }
	:global(.staff-records-parity .record-heading) { display: grid; gap: .3rem; min-width: 0; }
	:global(.staff-records-parity .record-heading strong) { font: italic 700 1.25rem var(--display); text-transform: uppercase; }
	:global(.staff-records-parity .record-reference) { font-size: .72rem; color: var(--muted); }
	:global(.staff-records-parity .record-bike) { margin-left: .2rem; }
	:global(.staff-records-parity .record-appointment) { display: grid; gap: .2rem; font-size: .78rem; }
	:global(.staff-records-parity .record-appointment > span:first-child) { display: inline-flex; align-items: center; gap: .35rem; }
	:global(.staff-records-parity .record-time) { color: var(--muted); padding-left: 1.15em; }
	:global(.staff-records-parity .record-status) { display: flex; justify-content: flex-end; align-items: center; gap: .65rem; }
	:global(.staff-records-parity .record-status .badge) { font-size: .75rem; }
	:global(.staff-records-parity .history-pagination) { display: flex; justify-content: flex-end; padding-block: .3rem; }
	:global(.staff-records-parity .history-empty) { display: grid; justify-items: center; gap: .7rem; text-align: center; padding: 2.5rem 1rem; border-style: dashed; }
	:global(.staff-records-parity .empty-icon) { display: grid; place-items: center; width: 2.8rem; height: 2.8rem; background: var(--panel-2); color: var(--muted); border-radius: 50%; font-size: 1.3rem; }
	:global(.staff-records-parity .history-empty h3) { font-size: 1.5rem; }
	:global(.staff-records-parity .history-empty p) { max-width: 23rem; font-size: .85rem; }
	@media (max-width: 700px) {
		:global(.staff-records-parity .history-filter-fields) { grid-template-columns: repeat(2, minmax(0, 1fr)); }
		:global(.staff-records-parity .history-search) { grid-column: 1 / -1; }
		:global(.staff-records-parity .booking-metrics) { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .5rem; }
		:global(.staff-records-parity .booking-metric) { gap: .5rem; padding: .75rem; }
		:global(.staff-records-parity .booking-metric:first-child) { grid-column: 1 / -1; grid-template-columns: 1fr 1fr; align-items: center; }
		:global(.staff-records-parity .booking-metric:first-child .metric-value) { justify-content: flex-end; gap: .75rem; }
		:global(.staff-records-parity .record-header) { grid-template-columns: minmax(0, 1fr) auto; gap: .5rem .75rem; }
		:global(.staff-records-parity .record-status) { grid-column: 2; grid-row: 1; }
		:global(.staff-records-parity .record-appointment) { grid-column: 1 / -1; grid-row: 2; display: flex; flex-wrap: wrap; align-items: center; gap: .6rem; font-size: .72rem; }
		:global(.staff-records-parity .record-time) { padding: 0; }
		:global(.staff-records-parity .record-bike) { display: none; }
		:global(.staff-records-parity .history-page-size) { display: none; }
		:global(.staff-records-parity .history-pagination) { justify-content: center; }
	}
	@media (max-width: 360px) {
		:global(.staff-records-parity .history-filters) { padding: .75rem; }
		:global(.staff-records-parity .history-filter-fields), :global(.staff-records-parity .history-date-fields) { gap: .65rem; }
		:global(.staff-records-parity .history-filters input), :global(.staff-records-parity .history-filters select) { padding-inline: .4rem; }
	}
	:global(.staff-records-parity .record-body) { padding-block: .6rem .25rem; overflow-wrap: anywhere; }
	:global(.staff-records-parity .record-details) { display: grid; gap: 12px; margin: 0; }
	:global(.staff-records-parity .record-details dt) { color: var(--muted); font-size: 0.85rem; }
	:global(.staff-records-parity .record-details dd) { margin: 0; overflow-wrap: anywhere; }
	:global(.staff-records-parity .booking-notes) { white-space: pre-wrap; overflow-wrap: anywhere; }

	:global(.staff-records-parity .ledger) { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px; padding-block: 12px; border-bottom: 1px solid var(--line); }
	:global(.staff-records-parity .success) { color: var(--ok); }
	:global(.staff-records-parity summary) { cursor: pointer; }
	:global(.staff-records-parity .cols) { grid-template-columns: repeat(auto-fit, minmax(min(100%, 230px), 1fr)); }


</style>
