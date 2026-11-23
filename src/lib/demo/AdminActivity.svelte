<script lang="ts">
	import { db } from './store.svelte';
	import { ops } from './operations.svelte';
	import Pager from '../shared/Pager.svelte';
	import { pageCount } from '../shared/paging.ts';

	const date = new Intl.DateTimeFormat('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'medium' });
	const events = $derived([...db.events, ...ops.data.events].sort((a, b) => b.at.localeCompare(a.at)));
	const modules = $derived([...new Set(events.map(event => event.module ?? 'Earlier activity'))].sort());
	let selectedModule = $state('');
	let search = $state('');
	const query = $derived(search.trim().toLowerCase());
	const visible = $derived(events.filter(event =>
		(!selectedModule || (event.module ?? 'Earlier activity') === selectedModule) &&
		[event.action, event.target, event.detail, event.bookingId, event.actor].some(value => value?.toLowerCase().includes(query))
	));
	// 10 entries per page (owner item 18); filters go back to page 1.
	const perPage = 10;
	let logPage = $state(1);
	const pages = $derived(pageCount(visible.length, perPage));
	const current = $derived(Math.min(logPage, pages));
</script>

<section class="card stack" aria-label="Activity entries">
	<div class="cols">
		<label>Module<select bind:value={selectedModule} onchange={() => (logPage = 1)}>
			<option value="">All modules</option>
			{#each modules as module (module)}<option value={module}>{module}</option>{/each}
		</select></label>
		<label>Search activity<input type="search" bind:value={search} oninput={() => (logPage = 1)} placeholder="Action, actor, item or reference" /></label>
	</div>
	<p class="muted small">{visible.length} {visible.length === 1 ? 'entry' : 'entries'} · Philippine time · Newest first</p>
	{#each visible.slice((current - 1) * perPage, current * perPage) as event (event.id)}
		<article class="entry stack">
			<div class="row entry-heading">
				<span class="module">{event.module ?? 'Earlier activity'}</span>
				<strong>{event.action}</strong>
			</div>
			{#if event.target || event.bookingId}<p>{event.target ?? event.bookingId}</p>{/if}
			{#if event.detail}<p class="muted small">{event.detail}</p>{/if}
			<p class="muted small">{event.actor} · <time datetime={event.at}>{date.format(new Date(event.at))}</time></p>
		</article>
	{:else}<p class="muted">No activity matches these filters.</p>{/each}
	<Pager page={current} {pages} label="Activity log" onchange={(next) => (logPage = next)} />
</section>

<style>
	.entry { gap: .35rem; border-top: 1px solid var(--line); padding-top: .75rem; overflow-wrap: anywhere; }
	.entry-heading { gap: .55rem; }
	.module { color: var(--accent); background: var(--panel-2); border-radius: .25rem; padding: .2rem .45rem; font-size: .8rem; font-weight: 700; }
</style>
