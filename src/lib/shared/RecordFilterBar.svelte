<script lang="ts">
	// Date chips in one sideways row. Search, status and source sit behind "Filters (n)".
	// Everything applies as soon as it changes; typing in search waits a moment first.
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
	<div class="chips" role="group" aria-label="Date range">
		{#each periods as period}
			<button type="button" class="chip" aria-pressed={filters.preset === period.value} onclick={() => { clearTimeout(timer); filters.preset = period.value; onchange(); }}>{period.label}</button>
		{/each}
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
	<div class="more-row">
		<details class="more">
			<summary>Filters ({count})</summary>
			<div class="fields">
				<label class="search">Search bookings<input type="search" bind:value={filters.search} oninput={typed} placeholder="Name, reference, mobile, bike or plate" maxlength="254" /></label>
				{#if showStatus}<label>Status<select bind:value={filters.status}><option value="all">All statuses</option>{#each Object.entries(statusLabels) as [value, label]}<option {value}>{label}</option>{/each}</select></label>{/if}
				<label>Booking source<select bind:value={filters.source}><option value="all">All sources</option><option value="online">Online</option><option value="walk-in">Walk-in</option></select></label>
			</div>
		</details>
		<button type="button" class="reset" onclick={() => { clearTimeout(timer); onreset(); }}>Reset filters</button>
	</div>
</div>

<style>
	.bar { display: grid; gap: .75rem; min-width: 0; }
	.chips { display: flex; gap: .4rem; overflow-x: auto; padding-bottom: .25rem; }
	.chip { flex: none; min-height: 2.75rem; padding: 0 1rem; border: 1px solid var(--line); border-radius: 99px; background: var(--panel); color: var(--text); font: 700 .85rem var(--body); cursor: pointer; white-space: nowrap; }
	.chip[aria-pressed='true'] { color: var(--accent-ink); background: var(--accent-fill); border-color: transparent; }
	.chip:hover:not([aria-pressed='true']) { background: var(--panel-2); }
	.dates { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 12rem), 1fr)); gap: .75rem; }
	.more-row { display: flex; flex-wrap: wrap; align-items: flex-start; justify-content: space-between; gap: .5rem; }
	.more { flex: 1 1 8rem; min-width: 0; }
	.more[open] { flex-basis: 100%; }
	summary { display: inline-flex; align-items: center; min-height: 2.75rem; padding: 0 .9rem; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); font: 700 .85rem var(--body); cursor: pointer; }
	.more[open] summary { border-color: var(--accent); }
	.fields { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 11rem), 1fr)); gap: .75rem; padding-top: .75rem; }
	.search { grid-column: 1 / -1; }
	label { font-size: .8rem; font-weight: 600; }
	.reset { display: inline-flex; align-items: center; min-height: 2.75rem; padding: 0 .6rem; border: 0; border-radius: 6px; background: transparent; color: var(--accent); font: 700 .85rem var(--body); cursor: pointer; }
	.reset:hover { background: var(--panel-2); }
</style>
