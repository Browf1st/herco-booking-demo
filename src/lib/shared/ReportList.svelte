<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// Reports list: a full-width table on desktop, one card per booking on phones.
	// Tapping a row (or its Details button) asks the screen to open the "More details" popup.
	import ActionIcon from './ActionIcon.svelte';
	import MoreIcons from './MoreIcons.svelte';
	import StatusBadge from './StatusBadge.svelte';
	import { initials, type ReportRow } from './report-ui';

	let { rows, showPrice, selectedId = '', onDetails }: { rows: ReportRow[]; showPrice: boolean; selectedId?: string; onDetails: (id: string) => void } = $props();
	const phoneLink = (phone: string) => 'tel:' + phone.replace(/[^\d+]/g, '');

	function openFromRow(event: MouseEvent, id: string) {
		const target = event.target as HTMLElement;
		if (target.closest('button, a')) return;
		(event.currentTarget as HTMLElement).querySelector('button')?.focus();
		onDetails(id);
	}
</script>

<table>
	<thead><tr><th>Customer &amp; vehicle</th><th>Date &amp; time</th><th>Services</th><th>Status</th>{#if showPrice}<th class="end">Price</th>{/if}<th class="end">Action</th></tr></thead>
	<tbody>
		{#each rows as row (row.id)}
			<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions (The Details button in each row is the keyboard way in.) -->
			<tr class:selected={row.id === selectedId} data-status={row.status} onclick={(event) => openFromRow(event, row.id)}>
				<td class="who">
					<span class="avatar" aria-hidden="true">{initials(row.name)}</span>
					<span class="who-text"><strong>{row.name}</strong><span class="bike">{row.bike}</span></span>
					<span class="ref">{row.ref}</span>
				</td>
				<td class="date">{row.date}<span class="time">{row.time}</span>{#if row.walkIn}<span class="walk">Walk-in</span>{/if}</td>
				<td class="services"><span class="chip">{row.services}</span></td>
				<td class="status"><StatusBadge status={row.status} /></td>
				{#if showPrice}<td class="end price" data-kind={row.priceKind ?? 'none'}>{row.price ?? '—'}</td>{/if}
				<td class="end"><button type="button" class="details-button" aria-label={'Details for ' + row.name} onclick={() => onDetails(row.id)}>Details</button></td>
				<td class="card-actions">
					<button type="button" class="details-button" aria-label={'Details for ' + row.name} onclick={() => onDetails(row.id)}>Details</button>
					{#if row.phone}<a class="call" href={phoneLink(row.phone)} aria-label={'Call ' + row.name}><MoreIcons name="phone" /></a>{/if}
				</td>
			</tr>
		{/each}
	</tbody>
</table>

<style>
	table { width: 100%; border-collapse: collapse; }
	th, td { padding: .7rem .8rem; text-align: left; vertical-align: middle; border-bottom: 1px solid var(--line); }
	th { color: var(--muted); font-size: .72rem; font-weight: 800; letter-spacing: .05em; text-transform: uppercase; background: var(--panel-2); }
	tbody tr { cursor: pointer; }
	tbody tr:hover { background: var(--panel-2); }
	tr.selected { background: var(--bad-bg); }
	tr.selected td:first-child { box-shadow: inset 4px 0 0 var(--accent-fill); }
	.who { display: grid; grid-template-columns: auto minmax(0, 1fr) auto; align-items: center; gap: .15rem .65rem; min-width: 14rem; }
	.avatar { display: grid; place-items: center; grid-row: span 2; width: 2.2rem; height: 2.2rem; border-radius: 50%; background: var(--panel-2); color: var(--muted); font-size: .8rem; font-weight: 800; }
	tr[data-status='done'] .avatar { background: var(--ok-bg); color: var(--ok); }
	tr.selected .avatar { background: var(--accent-fill); color: var(--accent-ink); }
	.who-text { display: grid; min-width: 0; }
	strong { overflow-wrap: anywhere; }
	.bike { color: var(--muted); font-size: .8rem; }
	.ref { padding: .05rem .45rem; border: 1px solid var(--line); border-radius: 6px; background: var(--panel-2); color: var(--accent); font-size: .72rem; font-weight: 800; }
	.date, .time { white-space: nowrap; }
	.time { display: block; color: var(--muted); font-size: .8rem; }
	.walk { display: inline-flex; align-items: center; gap: .3rem; color: light-dark(#6b21a8, #d8b4fe); font-size: .78rem; font-weight: 700; }
	.walk::before { content: ''; width: .45rem; height: .45rem; border-radius: 50%; background: currentColor; }
	.chip { padding: .1rem .55rem; border-radius: 6px; background: var(--info-bg); color: var(--info); font-size: .78rem; font-weight: 700; white-space: nowrap; }
	.end { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
	.price { font-weight: 600; }
	.price[data-kind='final'] { color: var(--ok); font-weight: 800; }
	.price[data-kind='none'] { color: var(--muted); }
	tr[data-status='cancelled'] :is(.avatar, .date, .chip, .who-text, .ref) { opacity: .6; }
	tr[data-status='cancelled'] .bike { text-decoration: line-through; }
	.details-button { min-height: 2.75rem; padding: 0 .9rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); color: var(--text); font: 700 .85rem var(--body); cursor: pointer; }
	.details-button:hover { border-color: var(--accent); color: var(--accent); }
	.details-button:focus-visible, .call:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
	.card-actions { display: none; }
	@media (max-width: 640px) {
		table, tbody { display: block; }
		thead, .end:not(.price) { display: none; }
		tr { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: .35rem .6rem; align-items: center; margin-bottom: .65rem; padding: .85rem; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); }
		tr.selected { background: var(--bad-bg); }
		tr.selected td:first-child { box-shadow: none; }
		td { padding: 0; border: 0; }
		.who { grid-column: 1; grid-template-columns: auto minmax(0, 1fr); min-width: 0; }
		.avatar { grid-row: span 3; }
		.ref { grid-column: 2; justify-self: start; }
		.status { grid-column: 2; grid-row: 1; justify-self: end; }
		.date { grid-column: 1; }
		.time { display: inline; margin-inline-start: .35rem; }
		.time::before { content: '· '; }
		.services { grid-column: 1; }
		.price { grid-column: 2; grid-row: 2 / 4; align-self: center; font-size: 1.05rem; }
		.card-actions { display: flex; grid-column: 1 / -1; align-items: center; gap: .5rem; }
		.card-actions .details-button { flex: 1; }
		.call { display: grid; place-items: center; width: 2.75rem; height: 2.75rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); color: var(--ok); text-decoration: none; }
	}
</style>
