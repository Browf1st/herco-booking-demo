<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// The "Booking records" card: heading, count chip, sort menu, the list and the "Showing x to y" footer.
	import Pager from './Pager.svelte';
	import ReportList from './ReportList.svelte';
	import { entryRange, sortOptions, sortReportRows, type ReportRow, type ReportSort } from './report-ui';

	// `sort` is bindable. When the screen sorts every record itself (`sortAll`), the rows arrive already in order.
	// `onsort` tells the screen the choice changed (the live screen then asks the server again).
	let { rows, total, page, pages, showPrice, selectedId = '', busy = false, sort = $bindable('date'), sortAll = false, onsort, onDetails, onpage }: {
		rows: ReportRow[]; total: number; page: number; pages: number; showPrice: boolean; selectedId?: string; busy?: boolean;
		sort?: ReportSort; sortAll?: boolean; onsort?: (sort: ReportSort) => void; onDetails: (id: string) => void; onpage: (page: number) => void;
	} = $props();
	const sorted = $derived(sortAll ? rows : sortReportRows(rows, sort));
	// Without the income permission the price order must not be offered (it would reveal amounts).
	const options = $derived(showPrice ? sortOptions : sortOptions.filter((option) => option.value !== 'price'));
	function choose(event: Event & { currentTarget: HTMLSelectElement }) {
		sort = event.currentTarget.value as ReportSort;
		onsort?.(sort);
	}
	const range = $derived(entryRange(page, pages, total, rows.length));
	const order = $derived(sort === 'date' ? 'Newest first' : sortOptions.find((option) => option.value === sort)?.label);
</script>

<section class="card records" aria-labelledby="records-heading" aria-busy={busy}>
	<div class="head">
		<div><h2 id="records-heading">Booking records</h2><p class="small muted">Showing active garage queue and completed logs</p></div>
		<div class="tools">
			<p class="chip small" role="status">{total} {total === 1 ? 'record' : 'records'} • {order}</p>
			<label class="sort">Sort<select value={sort} onchange={choose}>{#each options as option (option.value)}<option value={option.value}>{option.label}</option>{/each}</select></label>
		</div>
	</div>
	<div class="list"><ReportList rows={sorted} {showPrice} {selectedId} {onDetails} /></div>
	<div class="foot">
		<p class="small muted">Showing <b>{range.from}</b> to <b>{range.to}</b> of <b>{total}</b> {total === 1 ? 'entry' : 'entries'}</p>
		<Pager {page} {pages} label="Booking records" onchange={onpage} />
	</div>
</section>

<style>
	.records { padding: 0; overflow: hidden; }
	.records[aria-busy='true'] { opacity: .6; }
	.head { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .75rem 1rem; padding: 1rem 1.1rem; }
	h2 { font-size: 1.35rem; }
	.tools { display: flex; flex-wrap: wrap; align-items: center; gap: .6rem; }
	.chip { padding: .35rem .7rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel-2); font-weight: 700; }
	.sort { display: inline-flex; align-items: center; gap: .5rem; font-size: .8rem; font-weight: 700; }
	.sort select { width: auto; min-height: 2.5rem; }
	.list { overflow-x: auto; }
	.foot { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .5rem 1rem; padding: .8rem 1.1rem; border-top: 1px solid var(--line); }
	@media (max-width: 640px) {
		.records { padding: 0; border: 0; background: transparent; box-shadow: none; overflow: visible; }
		.head, .foot { padding-inline: 0; }
		.foot { border-top: 0; }
	}
</style>
