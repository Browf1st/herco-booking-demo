<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { addDays, today } from '#lib/dates.ts';
	type Entry = { recorded_at: string; area: string; action: string; actor: string; reference: string };
	const worker = import.meta.env.MODE === 'worker';
	const stamp = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' });
	let from = $state('');
	let through = $state('');
	let entries = $state<Entry[]>();
	let loading = $state(worker);
	let failure = $state('');

	async function load(event?: SubmitEvent) {
		event?.preventDefault();
		loading = true;
		entries = undefined;
		failure = '';
		try {
			const query = new URLSearchParams({ from, through });
			const response = await fetch(resolve('/api/staff/activity') + '?' + query);
			if (!response.ok) {
				const detail = await response.json().catch(() => null);
				throw new Error(detail?.message ?? 'The activity log is temporarily unavailable.');
			}
			entries = await response.json();
		} catch (error) {
			failure = error instanceof Error ? error.message : 'The activity log is temporarily unavailable.';
		} finally { loading = false; }
	}

	onMount(() => {
		if (!worker) return;
		through = today();
		from = addDays(through, -6);
		void load();
	});
</script>

<svelte:head><title>Activity log | HERCO</title></svelte:head>
<section class="section wrap stack">
	<h1>Activity log</h1>
	{#if worker}
		<form class="row card" onsubmit={load}>
			<label>From<input type="date" bind:value={from} required /></label>
			<label>Through<input type="date" bind:value={through} min={from || undefined} required /></label>
			<button class="btn sm" disabled={loading}>Apply date range</button>
		</form>
		{#if loading}<p role="status">Loading activity…</p>{/if}
		{#if failure}<p role="alert">{failure}</p>{/if}
		{#if entries}
			<p class="small muted">Showing up to 100 recent records in Philippine time.</p>
			<div class="stack">
				{#each entries as entry}
					<article class="card stack">
						<p><strong>{entry.area}</strong> · {entry.action.replaceAll('_', ' ')}</p>
						<p>{stamp.format(new Date(entry.recorded_at))}</p>
						<p class="small identity">Actor {entry.actor} · Reference {entry.reference}</p>
					</article>
				{:else}
					<p>No recorded activity in this date range.</p>
				{/each}
			</div>
		{/if}
	{:else}
		<p>The activity log is available in the server build.</p>
	{/if}
	<div><a class="btn sm ghost" href={resolve('/admin')}>Staff workspace</a></div>
</section>

<style>
	.identity { overflow-wrap: anywhere; }
</style>
