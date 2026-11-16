<script lang="ts">
	import { db } from './store.svelte';
	import { ops } from './operations.svelte';

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
</script>

<section class="card stack" aria-labelledby="activity-heading">
	<h3 id="activity-heading">Activity log</h3>
	<div class="cols">
		<label>Module<select bind:value={selectedModule}>
			<option value="">All modules</option>
			{#each modules as module (module)}<option value={module}>{module}</option>{/each}
		</select></label>
		<label>Search activity<input type="search" bind:value={search} placeholder="Action, actor, item or reference" /></label>
	</div>
	<p class="muted small">{visible.length} {visible.length === 1 ? 'entry' : 'entries'} · Philippine time · Newest first</p>
	{#each visible as event (event.id)}
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
</section>

<style>
	.entry { gap: .35rem; border-top: 1px solid var(--line); padding-top: .75rem; overflow-wrap: anywhere; }
	.entry-heading { gap: .55rem; }
	.module { color: var(--accent); background: var(--panel-2); border-radius: .25rem; padding: .2rem .45rem; font-size: .8rem; font-weight: 700; }
</style>
