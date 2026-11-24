<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// Reports summary: a dark income card (only when the viewer may see money) and five count cards.
	// On phones the counts fold into the income card. Only real numbers are shown.
	import { refsText } from './report-ui';

	type Counts = { total: number; completed: number; pending: number; booked: number; walkIns: number; cancelled: number };
	// `refs` lists booking references per group; the screen leaves a group out when it does not have the full list.
	let { income = null, counts, refs = {}, notes }: {
		income?: string | null; counts: Counts; refs?: { completed?: string[]; walkIns?: string[]; cancelled?: string[] }; notes: string[];
	} = $props();
	const completedRefs = $derived(refsText(refs.completed));
	const walkInRefs = $derived(refsText(refs.walkIns));
	const cancelledRefs = $derived(refsText(refs.cancelled));
	const completedLine = $derived(counts.completed === 1 ? 'completed service' : 'completed services');
</script>

<section class="summary" aria-label="Report summary">
	{#if income !== null}
		<div class="income" data-metric="income">
			<p class="label">Total income from completed services</p>
			<p class="amount">{income}</p>
			<p class="from">from <strong>{counts.completed} {completedLine}</strong>{#if completedRefs}{' '}<span>({completedRefs})</span>{/if}</p>
		</div>
	{/if}
	<dl class="cards" class:solo={income === null}>
		<div class="count total"><dt>Bookings in period</dt><dd>{counts.total}</dd><p class="sub">Total requests logged</p></div>
		<div class="count done"><dt>Completed services</dt><dd>{counts.completed}</dd><p class="sub"><span class="tag ok">Completed</span>{completedRefs}</p></div>
		<div class="count open"><dt>Pending and booked</dt><dd>{counts.pending + counts.booked}</dd><p class="sub">{counts.pending} pending • {counts.booked} booked</p></div>
		<div class="count walk"><dt>Walk-in bookings</dt><dd>{counts.walkIns}</dd><p class="sub">{walkInRefs || 'Direct visits'}</p></div>
		<div class="count gone"><dt>Cancelled bookings</dt><dd>{counts.cancelled}</dd><p class="sub">{cancelledRefs || 'Slot released'}</p></div>
	</dl>
	<details class="how"><summary>How these numbers are counted</summary>{#each notes as note}<p class="small muted">{note}</p>{/each}</details>
</section>

<style>
	.summary { display: grid; gap: .75rem; min-width: 0; }
	.income { padding: 1.1rem 1.3rem; border-radius: 12px; color: #f1f5f9; background: linear-gradient(120deg, #0b3b2c, #14202b 70%); border: 1px solid #ffffff22; }
	.label { color: #6ee7b7; font-size: .75rem; font-weight: 800; letter-spacing: .06em; text-transform: uppercase; }
	.amount { margin-top: .2rem; font-size: clamp(1.9rem, 5vw, 2.6rem); font-weight: 800; font-variant-numeric: tabular-nums; line-height: 1.15; }
	.from { color: #cbd5e1; font-size: .9rem; }
	.from strong { color: #fff; }
	dl { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: .7rem; margin: 0; }
	.count { display: grid; align-content: start; gap: .15rem; padding: .85rem 1rem; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); }
	dt { color: var(--muted); font-size: .72rem; font-weight: 800; letter-spacing: .04em; text-transform: uppercase; }
	dd { margin: 0; font-size: 2rem; font-weight: 800; line-height: 1.1; font-variant-numeric: tabular-nums; }
	.done dd { color: var(--ok); }
	.open dd { color: var(--warn); }
	.walk dd { color: light-dark(#6b21a8, #d8b4fe); }
	.gone dd { color: var(--bad); }
	.sub { display: flex; flex-wrap: wrap; align-items: center; gap: .35rem; color: var(--muted); font-size: .78rem; }
	.tag { padding: .05rem .5rem; border-radius: 99px; font-size: .68rem; font-weight: 800; }
	.ok { color: var(--ok); background: var(--ok-bg); }
	.how summary { display: inline-flex; align-items: center; min-height: 2.75rem; color: var(--muted); font-size: .85rem; font-weight: 700; text-decoration: underline dotted; cursor: pointer; }
	.how p { margin: .2rem 0; }
	@media (max-width: 999px) { dl { grid-template-columns: repeat(3, minmax(0, 1fr)); } }
	/* Phones: the counts sit inside the dark income card (3 across, then 2 small rows). */
	@media (max-width: 640px) {
		.summary { position: relative; }
		.income { border-radius: 14px 14px 0 0; }
		dl { gap: .5rem; padding: .75rem; border: 1px solid #ffffff22; border-top: 0; border-radius: 0 0 14px 14px; background: linear-gradient(120deg, #14202b, #0b3b2c); }
		dl.solo { margin-top: 0; border-top: 1px solid #ffffff22; border-radius: 14px; }
		.count { padding: .6rem; border-color: #ffffff22; background: #ffffff12; color: #f1f5f9; }
		.count:nth-child(n + 4) { grid-column: span 3; grid-template-columns: 1fr auto; align-items: center; }
		.count:nth-child(n + 4) .sub { grid-column: 1; }
		.count:nth-child(n + 4) dd { grid-row: 1 / 3; grid-column: 2; font-size: 1.5rem; }
		dt, .sub { color: #cbd5e1; }
		dd { font-size: 1.6rem; }
		.done dd { color: #6ee7b7; }
		.open dd { color: #fcd34d; }
		.walk dd { color: #d8b4fe; }
		.gone dd { color: #fda4af; }
		.how { padding-top: .1rem; }
	}
</style>
