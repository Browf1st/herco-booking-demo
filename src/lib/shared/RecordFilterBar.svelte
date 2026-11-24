<script lang="ts">
	// Date pills in one row (sideways scroll on phones), then Filters (n) and Reset filters.
	// Search, status and source sit behind "Filters (n)".
	// Everything applies as soon as it changes; typing in search waits a moment first.
	import ActionIcon from './ActionIcon.svelte';
	import { activeFilterCount, rangeIssue, statusLabels, type Period, type RecordFilters } from './records-ui';

	let { filters = $bindable(), periods, showStatus = true, onchange, onreset }: {
		filters: RecordFilters; periods: Period[]; showStatus?: boolean; onchange: () => void; onreset: () => void;
	} = $props();
	let timer: ReturnType<typeof setTimeout> | undefined;
	const count = $derived(activeFilterCount(filters, showStatus));
	const issue = $derived(rangeIssue(filters));

	function typed() {
		clearTimeout(timer);
		timer = setTimeout(onchange, 400);
	}
</script>

<!-- Dates and selects apply as soon as they change; typing in search has its own short wait. -->
<div class="bar" onchange={(event) => { if ((event.target as HTMLInputElement).type !== 'search') onchange(); }}>
	<div class="line">
		<div class="chips" role="group" aria-label="Date range">
			{#each periods as period}
				<button type="button" class="chip" aria-pressed={filters.preset === period.value} onclick={() => { clearTimeout(timer); filters.preset = period.value; onchange(); }}>{period.label}</button>
			{/each}
		</div>
		<span class="divider" aria-hidden="true"></span>
		<details class="more">
			<summary><ActionIcon name="adjust" />Filters ({count})</summary>
			<div class="fields">
				<label class="search">Search bookings<input type="search" bind:value={filters.search} oninput={typed} placeholder="Name, reference, mobile, bike or plate" maxlength="254" /></label>
				{#if showStatus}<label>Status<select bind:value={filters.status}><option value="all">All statuses</option>{#each Object.entries(statusLabels) as [value, label]}<option {value}>{label}</option>{/each}</select></label>{/if}
				<label>Booking source<select bind:value={filters.source}><option value="all">All sources</option><option value="online">Online</option><option value="walk-in">Walk-in</option></select></label>
			</div>
		</details>
		<button type="button" class="reset" onclick={() => { clearTimeout(timer); onreset(); }}><ActionIcon name="reset" />Reset filters</button>
	</div>
	{#if filters.preset === 'date'}
		<label>Appointment date<input type="date" bind:value={filters.exact} /></label>
	{:else if filters.preset === 'custom'}
		<div class="dates">
			<label>From<input type="date" bind:value={filters.from} /></label>
			<label>To<input type="date" bind:value={filters.through} /></label>
		</div>
	{/if}
	{#if issue}<p class="error" role="alert">{issue}</p>{/if}
</div>

<style>
	.bar { display: grid; gap: .75rem; min-width: 0; }
	.line { display: flex; align-items: center; gap: .6rem; min-width: 0; }
	.chips { display: flex; gap: .45rem; min-width: 0; overflow-x: auto; scrollbar-width: none; }
	.chips::-webkit-scrollbar { display: none; }
	.chip { flex: none; min-height: 2.75rem; padding: 0 1rem; border: 1px solid var(--line); border-radius: 99px; background: var(--panel-2); color: var(--text); font: 700 .85rem var(--body); cursor: pointer; white-space: nowrap; }
	.chip[aria-pressed='true'] { color: var(--accent-ink); background: var(--accent-fill); border-color: transparent; }
	.chip:hover:not([aria-pressed='true']) { border-color: var(--accent); }
	.divider { flex: none; align-self: stretch; width: 1px; margin-block: .3rem; background: var(--line); }
	.dates { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 12rem), 1fr)); gap: .75rem; }
	.more { position: relative; flex: none; }
	summary { display: inline-flex; align-items: center; gap: .4rem; min-height: 2.75rem; padding: 0 .9rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); font: 700 .85rem var(--body); cursor: pointer; list-style: none; }
	summary::-webkit-details-marker { display: none; }
	.more[open] summary { border-color: var(--accent); }
	.fields { position: absolute; z-index: 3; inset: calc(100% + .35rem) auto auto 0; display: grid; gap: .75rem; width: min(24rem, calc(100vw - 2rem)); padding: .85rem; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); box-shadow: 0 8px 24px var(--card-shadow); }
	label { font-size: .8rem; font-weight: 600; }
	.reset { display: inline-flex; flex: none; align-items: center; gap: .4rem; min-height: 2.75rem; margin-inline-start: auto; padding: 0 .6rem; border: 0; border-radius: 6px; background: transparent; color: var(--accent); font: 700 .85rem var(--body); cursor: pointer; }
	.reset:hover { text-decoration: underline; }
	@media (max-width: 640px) {
		.line { flex-wrap: wrap; }
		.chips { flex: 1 0 100%; }
		.divider { display: none; }
		.fields { position: static; width: auto; margin-top: .5rem; box-shadow: none; }
		.more[open] { flex: 1 0 100%; }
	}
</style>
