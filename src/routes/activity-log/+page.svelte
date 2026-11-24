<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import PageHeader from '#lib/shared/PageHeader.svelte';
	import Pager from '#lib/shared/Pager.svelte';
	import { pageCount } from '#lib/shared/paging.ts';
	import { addDays, today } from '#lib/shared/dates.ts';

	type Entry = { recorded_at: string; area: string; action: string; actor: string; actor_label?: string; reference: string };
	const worker = import.meta.env.MODE === 'worker';
	const stamp = new Intl.DateTimeFormat('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'medium' });
	let from = $state('');
	let through = $state('');
	let entries = $state<Entry[]>();
	let loading = $state(worker);
	let failure = $state('');
	let selectedModule = $state('');
	let search = $state('');

	const scheduleLabels: Record<string, string> = { set_default_hours: 'Changed opening hours and open days', set_date_hours: 'Set own hours for a date' };
	const label = (action: string) => {
		if (scheduleLabels[action]) return scheduleLabels[action];
		const text = action.replaceAll('_', ' ').trim();
		return text.charAt(0).toUpperCase() + text.slice(1);
	};
	const modules = $derived([...new Set((entries ?? []).map(entry => entry.area))].sort());
	const query = $derived(search.trim().toLowerCase());
	const visible = $derived((entries ?? []).filter(entry =>
		(!selectedModule || entry.area === selectedModule) &&
		(!query || [label(entry.action), entry.reference, entry.actor_label ?? entry.actor, entry.area].some(value => value.toLowerCase().includes(query)))));

	// 10 entries per page (owner item 18). Any filter, search or date change goes back to page 1.
	const perPage = 10;
	let logPage = $state(1);
	const pages = $derived(pageCount(visible.length, perPage));
	const current = $derived(Math.min(logPage, pages));
	const pageEntries = $derived(visible.slice((current - 1) * perPage, current * perPage));

	async function load(event?: SubmitEvent) {
		event?.preventDefault();
		logPage = 1;
		loading = true;
		failure = '';
		try {
			const response = await fetch(resolve('/api/staff/activity') + '?' + new URLSearchParams({ from, through }), { headers: { accept: 'application/json' } });
			if (!response.ok) {
				const detail = await response.json().catch(() => null);
				throw new Error(detail?.message ?? 'The activity log is temporarily unavailable.');
			}
			entries = await response.json();
			if (selectedModule && !entries?.some(entry => entry.area === selectedModule)) selectedModule = '';
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
	<PageHeader title="Activity log" subtitle="Who changed what in the staff workspace, newest first." timezone />
	{#if worker}
		<section class="card stack" aria-label="Activity entries">
			<form class="cols activity-dates" onsubmit={load}>
				<label>From<input type="date" bind:value={from} max={through || undefined} required /></label>
				<label>Through<input type="date" bind:value={through} min={from || undefined} required /></label>
				<div class="apply"><button class="btn sm" disabled={loading}><ActionIcon name="calendar" />{loading ? 'Loading…' : 'Apply dates'}</button></div>
			</form>
			<div class="cols">
				<label>Module<select bind:value={selectedModule} onchange={() => (logPage = 1)}>
					<option value="">All modules</option>
					{#each modules as module (module)}<option value={module}>{module}</option>{/each}
				</select></label>
				<label>Search activity<input type="search" bind:value={search} oninput={() => (logPage = 1)} placeholder="Action, actor, item or reference" /></label>
			</div>
			{#if failure}
				<p class="error" role="alert">{failure}</p>
				<div><button class="btn sm ghost" type="button" onclick={() => load()}><ActionIcon name="reset" />Try again</button></div>
			{:else if loading && !entries}
				<p role="status">Loading activity…</p>
			{:else if entries}
				<p class="muted small">{visible.length} {visible.length === 1 ? 'entry' : 'entries'} · Philippine time · Newest first{entries.length >= 100 ? ' · Showing the latest 100 for these dates' : ''}</p>
				{#each pageEntries as entry, index (entry.recorded_at + entry.reference + entry.action + index)}
					<article class="entry stack">
						<div class="row entry-heading">
							<span class="module">{entry.area}</span>
							<strong>{label(entry.action)}</strong>
						</div>
						{#if entry.reference}<p>{entry.reference}</p>{/if}
						<p class="muted small">{entry.actor_label ?? entry.actor} · <time datetime={entry.recorded_at}>{stamp.format(new Date(entry.recorded_at))}</time></p>
					</article>
				{:else}<p class="muted">No activity matches these filters.</p>{/each}
				<Pager page={current} {pages} label="Activity log" onchange={(next) => (logPage = next)} />
			{/if}
		</section>
	{:else}
		<p>The activity log is available in the server build.</p>
	{/if}
</section>

<style>
	.entry { gap: .35rem; border-top: 1px solid var(--line); padding-top: .75rem; overflow-wrap: anywhere; }
	.entry p { margin: 0; }
	.entry-heading { gap: .55rem; }
	.module { color: var(--accent); background: var(--panel-2); border-radius: .25rem; padding: .2rem .45rem; font-size: .8rem; font-weight: 700; }
	.activity-dates { align-items: end; }
	.apply { display: flex; align-items: end; }
</style>
