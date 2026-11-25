<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import DetailsSheet from '../shared/DetailsSheet.svelte';
	import Pager from '../shared/Pager.svelte';
	import { fmtDate, fmtSlot } from '../shared/dates';
	import { statusLabels, type RecordStatus } from '../shared/records-ui';
	import BookingNameGroup from './BookingNameGroup.svelte';

	type Group = { name: string; total: number };
	type Booking = { id: string; reference: string; date: string; hour: number | null; status: RecordStatus; bike: string };
	type Result = { total: number; groups?: Group[]; bookings?: Booking[] };
	let { surface, name, onclose }: { surface: 'customers' | 'history'; name?: string; onclose?: () => void } = $props();
	const pageSize = 20;
	let result = $state<Result>();
	let page = $state(1);
	let search = $state('');
	let query = '';
	let attemptedPage = 1;
	let loading = $state(true);
	let issue = $state('');
	let active: AbortController | undefined;
	let selected = $state<string>();

	async function load(next = 1) {
		active?.abort();
		const request = new AbortController();
		active = request;
		attemptedPage = next;
		loading = true;
		issue = '';
		try {
			const response = await fetch(resolve('/api/staff/booking-name-groups'), {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ surface, page: next, ...(name ? { name } : { q: query }) }),
				signal: request.signal
			});
			const data = await response.json().catch(() => null);
			if (request.signal.aborted) return;
			if (!response.ok || !data) throw new Error(data?.message ?? 'Booking groups are unavailable. Try again.');
			result = data;
			page = next;
		} catch (error) {
			if (!request.signal.aborted) issue = error instanceof Error ? error.message : 'Booking groups are unavailable. Try again.';
		} finally {
			if (!request.signal.aborted) loading = false;
		}
	}

	function submitSearch(event: SubmitEvent) {
		event.preventDefault();
		query = search.trim();
		void load();
	}

	onMount(() => {
		void load();
		return () => active?.abort();
	});
</script>

{#snippet contents()}
	<div class="stack">
		{#if loading}
			<p role="status">Loading booking groups…</p>
		{:else if issue}
			<p class="error" role="alert">{issue}</p>
			<div><button type="button" class="btn sm ghost" onclick={() => load(attemptedPage)}>Try again</button></div>
		{:else if result}
			{#if name}
				<p>Bookings with the same recorded name. Different people may share this name.</p>
				<p role="status">{result.total} {result.total === 1 ? 'booking' : 'bookings'}</p>
				{#each result.bookings ?? [] as booking (booking.id)}
					<div class="booking-row">
						<div><strong>{booking.reference}</strong> <span class="badge" data-status={booking.status === 'confirmed' ? 'booked' : booking.status}>{statusLabels[booking.status]}</span><p class="small muted">{booking.bike}</p></div>
						<span>{fmtDate(booking.date, { month: 'short', day: 'numeric', year: 'numeric' })}{booking.hour === null ? '' : ' · ' + fmtSlot(booking.hour + ':00')}</span>
					</div>
				{:else}
					<p>No bookings found for this name.</p>
				{/each}
			{:else}
				{#each result.groups ?? [] as group (group.name)}
					<button type="button" class="btn ghost group" onclick={() => selected = group.name}>
						<strong>{group.name}</strong>
						<span>{group.total} {group.total === 1 ? 'booking' : 'bookings'}</span>
					</button>
				{:else}
					<p>No matching booking names.</p>
				{/each}
			{/if}
			<Pager {page} pages={Math.ceil(result.total / pageSize)} label={name ? 'Same-name bookings' : 'Booking names'} onchange={load} />
		{/if}
	</div>
{/snippet}

{#if name && onclose}
	<DetailsSheet title={'Bookings recorded as ' + name} open onclose={onclose}>
		{@render contents()}
	</DetailsSheet>
{:else}
	<form class="row search" onsubmit={submitSearch}>
		<label>Search recorded names<input type="search" bind:value={search} maxlength="120" autocomplete="off" /></label>
		<button class="btn ghost">Search</button>
	</form>
	{@render contents()}
	{#if selected}
		<BookingNameGroup {surface} name={selected} onclose={() => selected = undefined} />
	{/if}
{/if}

<style>
	.search { align-items: end; flex-wrap: wrap; margin-block-end: 1rem; }
	.search label { flex: 1 1 14rem; }
	.group, .booking-row { justify-content: space-between; gap: .75rem; overflow-wrap: anywhere; }
	.group { width: 100%; text-align: start; flex-wrap: wrap; white-space: normal; }
	.booking-row { display: flex; flex-wrap: wrap; padding-block-end: .65rem; border-bottom: 1px solid var(--line); }
	.booking-row p { margin: .25rem 0 0; }
</style>
