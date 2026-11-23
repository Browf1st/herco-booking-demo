<script lang="ts">
	// Booking history: the totals, which also filter the list by status when tapped.
	let { tiles, selected, onpick }: { tiles: { value: string; label: string; count: number }[]; selected: string; onpick: (value: string) => void } = $props();
</script>

<div class="tiles" role="group" aria-label="Booking totals and status filters">
	{#each tiles as tile}
		<button type="button" class="card tile" data-status={tile.value} aria-pressed={selected === tile.value} onclick={() => onpick(tile.value)}>
			<span class="label">{tile.label}</span>
			<b>{tile.count}</b>
		</button>
	{/each}
</div>

<style>
	.tiles { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .5rem; }
	.tile { --tile-color: var(--text); display: grid; gap: .4rem; min-height: 2.75rem; padding: .75rem; text-align: left; color: var(--text); font: inherit; cursor: pointer; border-radius: 8px; }
	.tile:first-child { grid-column: 1 / -1; }
	.label { display: flex; align-items: center; gap: .4rem; font-size: .8rem; font-weight: 600; }
	.label::before { content: ""; width: .5rem; height: .5rem; flex: none; border-radius: 50%; background: var(--tile-color); }
	b { font-size: 1.7rem; line-height: 1; font-variant-numeric: tabular-nums; }
	.tile[data-status='pending'] { --tile-color: var(--warn); }
	.tile[data-status='confirmed'] { --tile-color: var(--accent); }
	.tile[data-status='done'] { --tile-color: var(--ok); }
	.tile[data-status='cancelled'] { --tile-color: var(--bad); }
	.tile:hover { background: var(--panel-2); }
	.tile[aria-pressed='true'] { border-color: var(--accent); box-shadow: inset 0 0 0 1px var(--accent); }
	@media (min-width: 700px) {
		.tiles { grid-template-columns: repeat(5, minmax(0, 1fr)); }
		.tile:first-child { grid-column: auto; }
	}
</style>
