<!-- Styles load together with this popup (not in the My bookings first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// The customer-facing change log for one booking: what changed, from/to pesos, You or Shop, and when (Philippine time).
	// Staff names, reasons and notes are never part of this answer, and this screen would ignore them anyway.
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { historyCap, historyLines, type HistoryEntry, type HistoryLine } from './customer-history';

	let { bookingId }: { bookingId: string } = $props();
	const preview = 8;
	let lines = $state<HistoryLine[]>();
	let failed = $state(false);
	let showAll = $state(false);
	const shown = $derived(lines && !showAll ? lines.slice(0, preview) : lines);

	async function load() {
		failed = false;
		lines = undefined;
		try {
			const response = await fetch(resolve('/api/bookings/history') + '?booking=' + encodeURIComponent(bookingId), { headers: { accept: 'application/json' } });
			if (!response.ok) throw new Error();
			const data = await response.json();
			lines = historyLines(Array.isArray(data.entries) ? (data.entries as HistoryEntry[]) : []);
		} catch { failed = true; }
	}
	onMount(() => { void load(); });
</script>

<section aria-label="Booking activity">
	<h4>Booking activity</h4>
	{#if failed}
		<p role="alert" class="small">Could not load booking activity.</p>
		<div><button type="button" class="btn sm ghost" onclick={load}>Try again</button></div>
	{:else if !lines}
		<p role="status" class="small muted">Loading booking activity…</p>
	{:else if !lines.length}
		<p class="small muted">No activity yet. Booking, price and service changes will show here.</p>
	{:else}
		<ol>
			{#each shown ?? [] as line (line.key)}
				<li><span class="text">{line.text}</span><span class="meta small muted"><b class:shop={line.actor === 'Shop'}>{line.actor}</b> · {line.when}</span></li>
			{/each}
		</ol>
		{#if lines.length > preview}
			<div><button type="button" class="btn sm ghost" aria-expanded={showAll} onclick={() => showAll = !showAll}>{showAll ? 'Show fewer' : 'Show all ' + lines.length}</button></div>
		{/if}
		{#if showAll && lines.length >= historyCap}<p class="small muted">Showing the latest {historyCap} changes.</p>{/if}
	{/if}
</section>

<style>
	section { display: grid; gap: .5rem; padding: .85rem; border: 1px solid var(--line); border-radius: 12px; }
	h4 { margin: 0; font-size: .75rem; letter-spacing: .05em; text-transform: uppercase; }
	p { margin: 0; }
	ol { display: grid; gap: .5rem; margin: 0; padding: 0; list-style: none; }
	li { display: grid; gap: .1rem; padding-inline-start: .6rem; border-inline-start: 3px solid var(--line); }
	.text { font-weight: 700; }
	.meta b { color: var(--accent); }
	.meta b:not(.shop) { color: var(--ok); }
</style>
