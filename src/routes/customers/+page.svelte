<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { resolve } from '$app/paths';
	import { fmtDate, fmtSlot } from '#lib/dates.ts';

	type Customer = { id: string; name: string | null; email: string };
	type Directory = { customers: Customer[]; nextCursor: string | null };
	type Visit = { id: string; visit_date: string; visit_hour: number | null;
		status: 'pending' | 'confirmed' | 'done' | 'cancelled' };
	type History = { visits: Visit[]; hasMore: boolean };
	type Lookup = { operation: 'directory'; term: string; cursor: string | null }
		| { operation: 'visits'; customer: string; page: number };

	const worker = import.meta.env.MODE === 'worker';
	const statusLabels = { pending: 'Pending', confirmed: 'Booked', done: 'Completed', cancelled: 'Cancelled' };
	let searchText = $state('');
	let runningTerm = $state('');
	let directory = $state<Directory>();
	let cursors = $state<(string | null)[]>([null]);
	let directoryPage = $state(0);
	let loading = $state(worker);
	let notice = $state('');
	let details = $state<Customer>();
	let history = $state<History>();
	let visitPage = $state(1);
	let visitsLoading = $state(false);
	let historyNotice = $state('');
	let detailsHeading = $state<HTMLHeadingElement>();
	let visitTrigger: HTMLButtonElement | undefined;
	let directoryRequest: AbortController | undefined;
	let visitsRequest: AbortController | undefined;
	let lastDirectoryRequest = { term: '', page: 0, cursor: null as string | null };

	async function lookup<T>(operation: Lookup, signal: AbortSignal): Promise<T> {
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

	function closeHistory() {
		visitsRequest?.abort();
		details = undefined;
		history = undefined;
		historyNotice = '';
	}

	function closeVisits() {
		closeHistory();
		visitTrigger?.focus();
	}

	async function loadDirectory(term: string, page: number, cursor: string | null) {
		lastDirectoryRequest = { term, page, cursor };
		directoryRequest?.abort();
		const active = new AbortController();
		directoryRequest = active;
		loading = true;
		notice = '';
		closeHistory();
		try {
			const result = await lookup<Directory>({ operation: 'directory', term, cursor }, active.signal);
			if (active.signal.aborted) return;
			directory = result;
			if (page === 0) cursors = [null];
			else cursors[page] = cursor;
			directoryPage = page;
			runningTerm = term;
		} catch (error) {
			if (active.signal.aborted) return;
			directory = undefined;
			notice = error instanceof Error ? error.message : 'Customer records are temporarily unavailable.';
		} finally {
			if (!active.signal.aborted) loading = false;
		}
	}

	function submitSearch(event: SubmitEvent) {
		event.preventDefault();
		void loadDirectory(searchText.trim(), 0, null);
	}

	async function loadVisits(customer: Customer, page: number, focus = false) {
		visitsRequest?.abort();
		const active = new AbortController();
		visitsRequest = active;
		details = customer;
		visitPage = page;
		history = undefined;
		historyNotice = '';
		visitsLoading = true;
		if (focus) {
			await tick();
			if (!active.signal.aborted) detailsHeading?.focus();
		}
		try {
			const result = await lookup<History>({ operation: 'visits', customer: customer.id, page }, active.signal);
			if (active.signal.aborted) return;
			history = result;
		} catch (error) {
			if (!active.signal.aborted) historyNotice = error instanceof Error ? error.message : 'Visits are temporarily unavailable.';
		} finally {
			if (!active.signal.aborted) visitsLoading = false;
		}
	}

	onMount(() => {
		if (worker) void loadDirectory('', 0, null);
		return () => {
			directoryRequest?.abort();
			visitsRequest?.abort();
		};
	});
</script>

<svelte:head><title>Staff customers | HERCO</title></svelte:head>
<section class="section wrap stack">
	<div class="row between">
		<h1>Customers</h1>
		<a class="btn sm ghost" href={resolve('/admin')}>Bookings</a>
	</div>
	{#if worker}
		<form class="card stack" onsubmit={submitSearch}>
			<label>Search by name or full email
				<input type="search" bind:value={searchText} placeholder="Name or full email" maxlength="254" autocomplete="off" />
			</label>
			<div class="row">
				<button class="btn sm" disabled={loading || searchText.trim().length === 1}>Search</button>
				{#if searchText || runningTerm}
					<button class="btn sm ghost" type="button" disabled={loading}
						onclick={() => { searchText = ''; void loadDirectory('', 0, null); }}>Clear search</button>
				{/if}
			</div>
		</form>
		{#if loading}
			<p role="status">Loading customers…</p>
		{:else if notice}
			<p class="error" role="alert">{notice}</p>
			<div class="row">
				<button class="btn sm ghost" type="button" onclick={() => {
					const { term, page, cursor } = lastDirectoryRequest;
					void loadDirectory(term, page, cursor);
				}}>Retry</button>
				<a href={resolve('/account')}>Account</a>
			</div>
		{:else if directory}
			<section class="card stack" aria-labelledby="directory-heading">
				<h2 id="directory-heading">Customer directory</h2>
				{#each directory.customers as customer (customer.id)}
					<article class="row between directory-row">
						<div>
							<strong>{customer.name || 'Name unavailable'}</strong>
							<p class="muted">{customer.email}</p>
						</div>
						<button class="btn sm ghost" type="button" aria-label={'View visits for ' + (customer.name || customer.email)}
							aria-expanded={details?.id === customer.id}
							onclick={(event) => {
								visitTrigger = event.currentTarget;
								void loadVisits(customer, 1, true);
							}}>View visits</button>
					</article>
				{:else}
					<p>No matching customers with verified accounts and bookings.</p>
				{/each}
				{#if directoryPage > 0 || directory.nextCursor}
					<nav class="row" aria-label="Customer pages">
						<button class="btn sm ghost" disabled={directoryPage === 0}
							onclick={() => loadDirectory(runningTerm, directoryPage - 1, cursors[directoryPage - 1])}>Previous</button>
						<span>Page {directoryPage + 1}</span>
						<button class="btn sm ghost" disabled={!directory.nextCursor}
							onclick={() => { if (directory?.nextCursor) void loadDirectory(runningTerm, directoryPage + 1, directory.nextCursor); }}>Next</button>
					</nav>
				{/if}
			</section>
		{/if}
		{#if details}
			{@const selected = details}
			<section class="card stack" aria-labelledby="visits-heading">
				<div class="row between">
					<h2 id="visits-heading" tabindex="-1" bind:this={detailsHeading}>Visits for {selected.name || selected.email}</h2>
					<button class="btn sm ghost" onclick={closeVisits}>Close visits</button>
				</div>
				{#if visitsLoading}
					<p role="status">Loading visits…</p>
				{:else if historyNotice}
					<p class="error" role="alert">{historyNotice}</p>
					<div><button class="btn sm ghost" onclick={() => loadVisits(selected, visitPage)}>Retry</button></div>
				{:else if history}
					<p class="muted small">Appointment times are shown in Philippine time.</p>
					{#each history.visits as visit (visit.id)}
						<div class="row between directory-row">
							<div>
								<strong>{fmtDate(visit.visit_date)}{visit.visit_hour === null ? ' · Walk-in' : ' at ' + fmtSlot(visit.visit_hour + ':00')}</strong>
								<p class="muted small">Reference {visit.id}</p>
							</div>
							<span class="badge" data-status={visit.status === 'confirmed' ? 'booked' : visit.status}>{statusLabels[visit.status]}</span>
						</div>
					{:else}
						<p>No visits on this page.</p>
					{/each}
					{#if visitPage > 1 || history.hasMore}
						<nav class="row" aria-label="Visit pages">
							<button class="btn sm ghost" disabled={visitPage === 1}
								onclick={() => loadVisits(selected, visitPage - 1)}>Previous</button>
							<span>Page {visitPage}</span>
							<button class="btn sm ghost" disabled={!history.hasMore}
								onclick={() => loadVisits(selected, visitPage + 1)}>Next</button>
						</nav>
					{/if}
				{/if}
			</section>
		{/if}
	{:else}
		<p>Open Customers from the demo staff workspace.</p>
	{/if}
</section>

<style>
	h2 { font-size: 1.8rem; }
	.directory-row { border-block-start: 1px solid var(--line); padding-block: .5rem; }
	.directory-row > div, h2 { min-width: 0; overflow-wrap: anywhere; }
</style>
