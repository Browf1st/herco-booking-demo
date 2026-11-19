<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { fmtDate, fmtSlot } from '#lib/dates.ts';

	type Request = {
		id: string;
		booking_id: string;
		kind: 'cancel' | 'reschedule';
		reason: string;
		customer_name: string;
		original_date: string;
		original_hour: number;
		target_date: string | null;
		target_hour: number | null;
		can_review: boolean;
	};
	const appointment = (date: string, hour: number) => fmtDate(date) + ' at ' + fmtSlot(hour + ':00');
	let requests = $state<Request[]>([]);
	let page = $state(1);
	let hasMore = $state(false);
	let status = $state<'loading' | 'ready' | 'signedOut' | 'verify' | 'denied' | 'failed'>('loading');
	let busy = $state(false);
	let error = $state('');
	let notice = $state('');

	async function load(nextPage = page) {
		status = 'loading';
		error = '';
		try {
			const response = await fetch(resolve('/api/staff/bookings') + '?view=requests&page=' + nextPage, {
				headers: { accept: 'application/json' }
			});
			if (response.status === 401) status = 'signedOut';
			else if (response.status === 428) status = 'verify';
			else if (response.status === 403) status = 'denied';
			else if (!response.ok) throw new Error();
			else {
				const data = await response.json();
				page = nextPage;
				requests = data.requests;
				hasMore = data.hasMore;
				status = 'ready';
			}
		} catch {
			status = 'failed';
		}
	}

	async function review(requestId: string, decision: 'approved' | 'declined') {
		if (busy) return;
		busy = true;
		error = notice = '';
		try {
			const response = await fetch(resolve('/api/staff/bookings'), {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ action: 'review', requestId, decision })
			});
			if (!response.ok) {
				const failure = await response.json().catch(() => null);
				throw new Error(typeof failure?.message === 'string' ? failure.message : 'Could not save the decision.');
			}
			await load(requests.length === 1 && page > 1 ? page - 1 : page);
			notice = decision === 'approved' ? 'Request approved.' : 'Request declined.';
		} catch (failure) {
			error = failure instanceof Error ? failure.message : 'Could not save the decision.';
		} finally {
			busy = false;
		}
	}

	onMount(() => { void load(); });
</script>

<svelte:head><title>Booking change requests | HERCO</title></svelte:head>
<section class="section wrap stack">
	<h1>Booking change requests</h1>
	{#if status === 'signedOut' || status === 'verify'}
		<p>{status === 'signedOut' ? 'Sign in with your staff account.' : 'Verify your staff session with your authenticator.'}</p>
		<div><a class="btn sm" href={resolve('/account')}>Go to Account</a></div>
	{:else if status === 'denied'}
		<p role="alert">Your account does not have access to change requests.</p>
	{:else if status === 'failed'}
		<p role="alert">Could not load change requests.</p>
		<div><button class="btn sm ghost" onclick={() => load()}>Try again</button></div>
	{:else if status === 'loading'}
		<p role="status">Loading change requests…</p>
	{:else}
		<p class="muted">Visit times are in Philippine time.</p>
		{#if !requests.length}<p>No pending requests on this page.</p>{/if}
		{#each requests as request (request.id)}
			<article class="card stack">
				<h2>{request.kind === 'cancel' ? 'Cancellation' : 'Rescheduling'} · {request.customer_name}</h2>
				<p>Current visit · {appointment(request.original_date, request.original_hour)}</p>
				{#if request.target_date && request.target_hour !== null}
					<p>Requested visit · {appointment(request.target_date, request.target_hour)}</p>
				{/if}
				{#if request.reason}<p>Customer reason · {request.reason}</p>{/if}
				{#if request.can_review}
					<div class="row">
						<button class="btn sm" disabled={busy} onclick={() => review(request.id, 'approved')}>Approve request</button>
						<button class="btn sm ghost" disabled={busy} onclick={() => review(request.id, 'declined')}>Decline request</button>
					</div>
				{/if}
			</article>
		{/each}
		{#if page > 1 || hasMore}
			<nav class="row" aria-label="Change request pages">
				<button class="btn sm ghost" disabled={busy || page === 1} onclick={() => load(page - 1)}>Previous</button>
				<span>Page {page}</span>
				<button class="btn sm ghost" disabled={busy || !hasMore} onclick={() => load(page + 1)}>Next</button>
			</nav>
		{/if}
	{/if}
	{#if error}<p role="alert">{error}</p>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
</section>
