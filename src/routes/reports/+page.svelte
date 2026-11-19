<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { today } from '#lib/dates.ts';
	const worker = import.meta.env.MODE === 'worker';
	const currency = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
	type Report = { total: number; pending: number; booked: number; cancelled: number; completed: number;
		completedWithoutValue: number | null; completedValueCentavos: number | null; valueCorrectionsCentavos?: number | null };
	let from = $state('');
	let to = $state('');
	let loading = $state(worker);
	let report = $state<Report>();
	let failure = $state('');

	async function load(event?: SubmitEvent) {
		event?.preventDefault();
		loading = true;
		report = undefined;
		failure = '';
		try {
			const query = new URLSearchParams({ from, to });
			const response = await fetch(resolve('/api/reports') + '?' + query);
			if (!response.ok) {
				const detail = await response.json().catch(() => null);
				throw new Error(detail?.message ?? 'Reports are temporarily unavailable.');
			}
			report = await response.json();
		} catch (error) {
			failure = error instanceof Error ? error.message : 'Reports are temporarily unavailable.';
		} finally {
			loading = false;
		}
	}

	onMount(() => {
		if (!worker) return;
		to = today();
		from = to.slice(0, 8) + '01';
		void load();
	});
</script>

<svelte:head><title>Booking reports | HERCO</title></svelte:head>
<section class="section wrap stack">
	<h1>Booking reports</h1>
	{#if worker}
		<form class="card stack" onsubmit={load}>
			<p>Filter by scheduled visit date in Philippine time.</p>
			<div class="row">
				<label>From<input type="date" bind:value={from} required /></label>
				<label>Through<input type="date" bind:value={to} min={from || undefined} required /></label>
			</div>
			<div><button class="btn sm" disabled={loading}>Apply date range</button></div>
		</form>
		{#if loading}<p role="status">Loading report…</p>{/if}
		{#if failure}<p role="alert">{failure}</p>{/if}
		{#if report}
			<dl class="card stack">
				<div class="row between"><dt>Total bookings</dt><dd>{report.total}</dd></div>
				<div class="row between"><dt>Pending</dt><dd>{report.pending}</dd></div>
				<div class="row between"><dt>Booked</dt><dd>{report.booked}</dd></div>
				<div class="row between"><dt>Completed</dt><dd>{report.completed}</dd></div>
				<div class="row between"><dt>Cancelled</dt><dd>{report.cancelled}</dd></div>
				{#if report.completedValueCentavos !== null}
					<div class="row between"><dt>Completed service value</dt><dd>{currency.format(report.completedValueCentavos / 100)}</dd></div>
				{/if}
				{#if report.valueCorrectionsCentavos}
					<div class="row between"><dt>Net price corrections included</dt><dd>{currency.format(report.valueCorrectionsCentavos / 100)}</dd></div>
				{/if}
			</dl>
			{#if report.completedWithoutValue}<p>{report.completedWithoutValue} completed bookings have no recorded final price.</p>{/if}
		{/if}
	{:else}
		<p>This workspace is available in the server build.</p>
	{/if}
	<div><a class="btn sm ghost" href={resolve('/admin')}>Staff workspace</a></div>
</section>
