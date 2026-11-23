<script lang="ts">
	// Reports summary: income first and large (when the viewer may see it), then the other numbers in a grid.
	let { income = null, items, notes }: { income?: string | null; items: [string, number][]; notes: string[] } = $props();
</script>

<section class="summary" aria-label="Report summary">
	<dl>
		{#if income !== null}<div class="card income" data-metric="income"><dt>Total income from completed services</dt><dd>{income}</dd></div>{/if}
		{#each items as [label, value]}<div class="card"><dt>{label}</dt><dd>{value}</dd></div>{/each}
	</dl>
	<details class="how"><summary>How these numbers are counted</summary>{#each notes as note}<p class="small muted">{note}</p>{/each}</details>
</section>

<style>
	.summary { display: grid; gap: .6rem; min-width: 0; }
	dl { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .6rem; margin: 0; }
	div { padding: .75rem; }
	dt { font-size: .75rem; font-weight: 700; letter-spacing: .04em; text-transform: uppercase; }
	dd { margin: .3rem 0 0; font-size: 1.5rem; font-weight: 750; font-variant-numeric: tabular-nums; }
	.income { grid-column: 1 / -1; padding: 1rem; }
	.income dd { margin-top: .4rem; font-size: 2rem; color: var(--ok); }
	.how summary { display: inline-flex; align-items: center; min-height: 2.75rem; color: var(--muted); font-size: .85rem; font-weight: 700; cursor: pointer; }
	.how p { margin: .2rem 0; }
	@media (min-width: 600px) { dl { grid-template-columns: repeat(3, minmax(0, 1fr)); } }
	@media (min-width: 1000px) { dl { grid-template-columns: repeat(5, minmax(0, 1fr)); } }
</style>
