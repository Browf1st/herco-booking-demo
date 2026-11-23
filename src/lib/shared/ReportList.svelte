<script lang="ts">
	// Reports list: a table with 5 columns on desktop, one card per booking on phones.
	// Tapping a row (or its Details button) asks the screen to open the details sheet.
	import StatusBadge from './StatusBadge.svelte';
	import type { ReportRow } from './records-ui';

	let { rows, showPrice, onDetails }: { rows: ReportRow[]; showPrice: boolean; onDetails: (id: string) => void } = $props();

	function openFromRow(event: MouseEvent, id: string) {
		const target = event.target as HTMLElement;
		if (target.closest('button')) return;
		(event.currentTarget as HTMLElement).querySelector('button')?.focus();
		onDetails(id);
	}
</script>

<table>
	<thead><tr><th>Customer</th><th>Date</th><th>Services</th><th>Status</th><th class="end">{showPrice ? 'Price' : 'Details'}</th></tr></thead>
	<tbody>
		{#each rows as row (row.id)}
			<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions (The Details button in each row is the keyboard way in.) -->
			<tr onclick={(event) => openFromRow(event, row.id)}>
				<td class="who"><strong>{row.name}</strong><div class="small muted">{row.ref}</div></td>
				<td class="date">{row.date}<div class="small muted time">{row.time}</div></td>
				<td class="services">{row.services}</td>
				<td class="status"><StatusBadge status={row.status} /></td>
				<td class="end">{#if showPrice}<span class="price">{row.price ?? '—'}</span>{/if}<button type="button" class="details-button" aria-label={'Details for ' + row.name} onclick={() => onDetails(row.id)}>Details</button></td>
			</tr>
		{/each}
	</tbody>
</table>

<style>
	table { width: 100%; border-collapse: collapse; }
	th, td { padding: .6rem .7rem; text-align: left; vertical-align: top; border-bottom: 1px solid var(--line); }
	th { font-size: .75rem; font-weight: 700; letter-spacing: .04em; text-transform: uppercase; background: var(--panel-2); }
	tbody tr { cursor: pointer; }
	tbody tr:hover { background: var(--panel-2); }
	.end { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
	.price { font-weight: 700; }
	.details-button { min-height: 2.75rem; padding: 0 .5rem; margin-inline-start: .5rem; border: 0; background: transparent; color: var(--accent); font: 700 .9rem var(--body); cursor: pointer; }
	.details-button:hover { text-decoration: underline; }
	.details-button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
	@media (max-width: 699px) {
		table, tbody { display: block; }
		thead { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); }
		tr { display: grid; grid-template-columns: auto minmax(0, 1fr) auto; gap: .15rem .6rem; align-items: center; margin-bottom: .6rem; padding: .75rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); }
		td { padding: 0; border: 0; }
		.who { grid-column: 1 / 3; }
		.status { grid-column: 3; grid-row: 1; justify-self: end; }
		.date { grid-column: 1; grid-row: 2; }
		.time { display: none; }
		.services { grid-column: 2 / 4; grid-row: 2; }
		.services::before { content: '· '; }
		.end { grid-column: 1 / -1; display: flex; align-items: center; justify-content: space-between; text-align: left; }
		.price { font-size: 1.1rem; }
		.details-button { margin-inline-start: auto; }
	}
</style>
