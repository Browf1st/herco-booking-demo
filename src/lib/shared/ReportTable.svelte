<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// The "Booking records" card: heading, search box, sort menu, the list and the "Showing x to y" footer.
	import Pager from './Pager.svelte';
	import RecordsEmpty from './RecordsEmpty.svelte';
	import ReportList from './ReportList.svelte';
	import { entryRange, isPriceSort, sortOptions, sortReportRows, type ReportRow, type ReportSort } from './report-ui';

	// `sort` and `search` are bindable. When the screen sorts every record itself (`sortAll`), the rows arrive already in order.
	// `onsort` / `onsearch` tell the screen the choice changed (the live screen then asks the server again).
	// The table stays on screen when nothing matches, so the search box can be cleared.
	let { rows, total, page, pages, showPrice, selectedId = '', busy = false, sort = $bindable('date'), search = $bindable(''), sortAll = false, onsort, onsearch, onreset, onDetails, onpage }: {
		rows: ReportRow[]; total: number; page: number; pages: number; showPrice: boolean; selectedId?: string; busy?: boolean;
		sort?: ReportSort; search?: string; sortAll?: boolean; onsort?: (sort: ReportSort) => void; onsearch?: () => void; onreset: () => void;
		onDetails: (id: string) => void; onpage: (page: number) => void;
	} = $props();
	const sorted = $derived(sortAll ? rows : sortReportRows(rows, sort));
	// Without the income permission the price orders must not be offered (they would reveal amounts).
	const options = $derived(showPrice ? sortOptions : sortOptions.filter((option) => !isPriceSort(option.value)));
	function choose(event: Event & { currentTarget: HTMLSelectElement }) {
		sort = event.currentTarget.value as ReportSort;
		onsort?.(sort);
	}
	const range = $derived(entryRange(page, pages, total, rows.length));

	// What is typed in the box. It is applied after a short pause (like the old search in Filters).
	let text = $state('');
	let timer: ReturnType<typeof setTimeout> | undefined;
	$effect(() => { text = search; }); // follows "Reset filters"
	function typed() {
		clearTimeout(timer);
		timer = setTimeout(() => { search = text; onsearch?.(); }, 300);
	}
</script>

<section class="card records" aria-labelledby="records-heading" aria-busy={busy}>
	<div class="head">
		<div><h2 id="records-heading">Booking records</h2><p class="small muted">Showing active garage queue and completed logs</p></div>
		<div class="tools">
			<label class="find"><span class="sr-only">Search booking records</span><input type="search" bind:value={text} oninput={typed} placeholder="Search name, ref, bike or phone" maxlength="254" /></label>
			<label class="sort">Sort<select value={sort} onchange={choose}>{#each options as option (option.value)}<option value={option.value}>{option.label}</option>{/each}</select></label>
		</div>
	</div>
	{#if total === 0}
		<RecordsEmpty title="No bookings found" text="Try another date, status or search to find your bookings." action="Reset filters" onaction={onreset} />
	{:else}
		<div class="list"><ReportList rows={sorted} {showPrice} {selectedId} {onDetails} /></div>
		<div class="foot">
			<p class="small muted">Showing <b>{range.from}</b> to <b>{range.to}</b> of <b>{total}</b> {total === 1 ? 'entry' : 'entries'}</p>
			<Pager {page} {pages} label="Booking records" onchange={onpage} />
		</div>
	{/if}
</section>

<style>
	.records { padding: 0; overflow: hidden; }
	.records[aria-busy='true'] { opacity: .6; }
	.head { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .75rem 1rem; padding: 1rem 1.1rem; }
	h2 { font-size: 1.35rem; }
	.tools { display: flex; flex-wrap: wrap; align-items: center; gap: .6rem; }
	.sr-only { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
	.find input { width: min(20rem, 100%); min-height: 2.5rem; }
	.sort { display: inline-flex; align-items: center; gap: .5rem; font-size: .8rem; font-weight: 700; }
	.sort select { width: auto; min-height: 2.5rem; }
	.list { overflow-x: auto; }
	.foot { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .5rem 1rem; padding: .8rem 1.1rem; border-top: 1px solid var(--line); }
	@media (max-width: 640px) {
		.records { padding: 0; border: 0; background: transparent; box-shadow: none; overflow: visible; }
		.head, .foot { padding-inline: 0; }
		.tools, .find, .find input { width: 100%; }
		.sort { justify-content: space-between; width: 100%; }
		.sort select { flex: 1; }
		.foot { border-top: 0; }
	}
</style>
