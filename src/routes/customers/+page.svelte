<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { fmtDate, fmtSlot } from '#lib/shared/dates.ts';

	type Status = 'pending' | 'confirmed' | 'done' | 'cancelled';
	type Customer = { id: string; name: string | null; email: string; phone: string | null; bike: string | null; booking_count: number; points: number };
	type Directory = { customers: Customer[]; nextCursor: string | null; total: number };
	type Visit = { id: string; reference: string; visit_date: string; visit_hour: number | null; status: Status; bike: string; services: string[]; source: 'online' | 'walk-in' };
	type History = { visits: Visit[]; hasMore: boolean };
	type Lookup = { operation: 'directory'; term: string; cursor: string | null } | { operation: 'visits'; customer: string; page: number };

	const worker = import.meta.env.MODE === 'worker';
	const pageSize = 20;
	const statusLabels: Record<Status, string> = { pending: 'Pending', confirmed: 'Booked', done: 'Completed', cancelled: 'Cancelled' };
	let search = $state('');
	let runningTerm = $state('');
	let directory = $state<Directory>();
	let cursors = $state<(string | null)[]>([null]);
	let directoryPage = $state(0);
	let loading = $state(worker);
	let notice = $state('');
	let histories = $state<Record<string, { state: 'loading' | 'ready' | 'failed'; page: number; data?: History; message?: string }>>({});
	let directoryRequest: AbortController | undefined;
	let searchTimer: ReturnType<typeof setTimeout> | undefined;

	async function lookup<T>(operation: Lookup, signal?: AbortSignal): Promise<T> {
		const response = await fetch(resolve('/api/staff/customers'), {
			method: 'POST', signal,
			headers: { 'content-type': 'application/json', accept: 'application/json' },
			body: JSON.stringify(operation)
		});
		if (!response.ok) {
			const failure = await response.json().catch(() => null);
			throw new Error(failure?.message ?? 'Customer records are temporarily unavailable.');
		}
		return response.json();
	}

	async function loadDirectory(term: string, page: number, cursor: string | null) {
		directoryRequest?.abort();
		const active = new AbortController();
		directoryRequest = active;
		loading = true;
		notice = '';
		try {
			const result = await lookup<Directory>({ operation: 'directory', term, cursor }, active.signal);
			if (active.signal.aborted) return;
			directory = result;
			if (page === 0) cursors = [null];
			cursors[page] = cursor;
			directoryPage = page;
			runningTerm = term;
			histories = {};
		} catch (error) {
			if (active.signal.aborted) return;
			directory = undefined;
			notice = error instanceof Error ? error.message : 'Customer records are temporarily unavailable.';
		} finally {
			if (!active.signal.aborted) loading = false;
		}
	}

	function searchChanged() {
		clearTimeout(searchTimer);
		const term = search.trim();
		// The server needs two characters to search; a single character keeps the current list.
		if (term.length === 1) return;
		searchTimer = setTimeout(() => { if (term !== runningTerm || !directory) void loadDirectory(term, 0, null); }, 300);
	}

	async function loadVisits(customer: Customer, page: number) {
		histories[customer.id] = { state: 'loading', page };
		try {
			const data = await lookup<History>({ operation: 'visits', customer: customer.id, page });
			histories[customer.id] = { state: 'ready', page, data };
		} catch (error) {
			histories[customer.id] = { state: 'failed', page, message: error instanceof Error ? error.message : 'Visits are temporarily unavailable.' };
		}
	}

	function toggled(event: Event, customer: Customer) {
		if ((event.currentTarget as HTMLDetailsElement).open && !histories[customer.id]) void loadVisits(customer, 1);
	}

	const offset = $derived(directoryPage * pageSize);

	onMount(() => {
		if (worker) void loadDirectory('', 0, null);
		return () => { directoryRequest?.abort(); clearTimeout(searchTimer); };
	});
</script>

<svelte:head><title>Customers | HERCO</title></svelte:head>
<section class="section wrap stack customers-page">
	<h3>Customers</h3>
	{#if worker}
		<div class="card customer-total"><span class="muted small">Total accounts</span><b>{directory ? directory.total.toLocaleString('en-PH') : '—'}</b></div>
		<label>Search customers<input type="search" bind:value={search} oninput={searchChanged} placeholder="Name, email, mobile number or account ID" maxlength="254" autocomplete="off" /></label>
		{#if loading && !directory}
			<p role="status">Loading customers…</p>
		{:else if notice}
			<p class="error" role="alert">{notice}</p>
			<div class="row">
				<button class="btn sm ghost" type="button" onclick={() => loadDirectory(runningTerm, directoryPage, cursors[directoryPage] ?? null)}><ActionIcon name="reset" />Try again</button>
			</div>
		{:else if directory}
			<div class="stack" aria-busy={loading}>
				{#each directory.customers as customer (customer.id)}
					{@const history = histories[customer.id]}
					<details class="card customer-record" ontoggle={(event) => toggled(event, customer)}>
						<summary>
							<span><b>{customer.name || customer.email}</b> <span class="muted small">{customer.id.slice(0, 8)}</span></span>
							<span class="customer-record-meta">{customer.bike ?? ''} <span class="badge">{customer.booking_count} {customer.booking_count === 1 ? 'booking' : 'bookings'}</span></span>
						</summary>
						<div class="stack customer-profile">
							<div class="cols customer-details">
								<div><span class="muted small">Mobile</span><p>{#if customer.phone}<a href={'tel:' + customer.phone}>{customer.phone}</a>{:else}Not provided{/if}</p></div>
								<div><span class="muted small">Email</span><p><a href={'mailto:' + customer.email}>{customer.email}</a></p></div>
								<div><span class="muted small">HERCO Points</span><p>{Number(customer.points).toLocaleString('en-PH')}</p></div>
							</div>
							<h3>Booking history ({customer.booking_count})</h3>
							{#if !history || history.state === 'loading'}
								<p role="status" class="muted">Loading bookings…</p>
							{:else if history.state === 'failed'}
								<p class="error" role="alert">{history.message}</p>
								<div><button class="btn sm ghost" type="button" onclick={() => loadVisits(customer, history.page)}><ActionIcon name="reset" />Try again</button></div>
							{:else if history.data}
								{#each history.data.visits as visit (visit.id)}
									<div class="ledger">
										<div><span class="badge" data-status={visit.status === 'confirmed' ? 'booked' : visit.status}>{statusLabels[visit.status]}</span> <b>{visit.services.join(' · ') || 'Service'}</b><p class="muted small">{visit.bike} · {visit.reference}{visit.source === 'walk-in' ? ' · Walk-in' : ''}</p></div>
										<span class="small">{fmtDate(visit.visit_date, { month: 'short', day: 'numeric', year: 'numeric' })}{visit.visit_hour === null ? '' : ' · ' + fmtSlot(visit.visit_hour + ':00')}</span>
									</div>
								{:else}<p class="muted">No linked bookings yet.</p>{/each}
								{#if history.page > 1 || history.data.hasMore}
									<nav class="row" aria-label="Booking history pagination">
										<button type="button" class="btn sm ghost" disabled={history.page <= 1} onclick={() => loadVisits(customer, history.page - 1)}><ActionIcon name="left" />Previous</button>
										<span class="small muted">Page {history.page}</span>
										<button type="button" class="btn sm ghost" disabled={!history.data.hasMore} onclick={() => loadVisits(customer, history.page + 1)}><ActionIcon name="right" />Next</button>
									</nav>
								{/if}
							{/if}
						</div>
					</details>
				{:else}<p class="muted">No matching customers.</p>{/each}
			</div>
			{#if directory.customers.length}
				<div class="row between">
					<span class="small muted" aria-live="polite">Showing {offset + 1}–{offset + directory.customers.length}{runningTerm ? '' : ' of ' + directory.total} accounts</span>
					{#if directoryPage > 0 || directory.nextCursor}
						<nav class="row" aria-label="Customers pagination">
							<button type="button" class="btn sm ghost" disabled={loading || directoryPage === 0} onclick={() => loadDirectory(runningTerm, directoryPage - 1, cursors[directoryPage - 1] ?? null)}><ActionIcon name="left" />Previous</button>
							<span class="small muted">Page {directoryPage + 1}</span>
							<button type="button" class="btn sm ghost" disabled={loading || !directory.nextCursor} onclick={() => { if (directory?.nextCursor) void loadDirectory(runningTerm, directoryPage + 1, directory.nextCursor); }}><ActionIcon name="right" />Next</button>
						</nav>
					{/if}
				</div>
			{/if}
		{/if}
	{:else}
		<p>Open Customers from the demo staff workspace.</p>
	{/if}
</section>

<style>
	.customers-page h3 { overflow-wrap: anywhere; }
	.customer-total { display: grid; gap: .25rem; }
	.customer-total b { font-size: 1.6rem; }
	.customer-record { padding: 0; overflow-wrap: anywhere; }
	.customer-record > summary { padding: .65rem .9rem; cursor: pointer; }
	.customer-record[open] > summary { background: var(--panel-2); border-radius: 6px 6px 0 0; }
	.customer-record-meta { display: inline-flex; flex-wrap: wrap; align-items: center; gap: .4rem; margin-inline-start: .55rem; color: var(--muted); font-size: .85rem; }
	.customer-profile { padding: .9rem; }
	.customer-details { background: var(--bg); border: 1px solid var(--line); padding: .7rem; border-radius: 4px; }
	.customer-details p { margin: 0; }
	.ledger { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px; padding-block: 12px; border-bottom: 1px solid var(--line); }
	.ledger p { margin: .15rem 0 0; }
</style>
