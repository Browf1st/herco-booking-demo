<script lang="ts">
	// One row with the reward name on the left (2 lines at most) and its point cost on the right.
	let { name, points, tag = 'h3' }: { name: string; points: number; tag?: 'h3' | 'span' } = $props();
</script>

<div class="reward-heading">
	{#if tag === 'h3'}<h3 class="reward-title" title={name}>{name}</h3>{:else}<span class="reward-title" title={name}>{name}</span>{/if}
	<strong class="reward-cost">{points.toLocaleString('en-PH')} pts</strong>
</div>

<style>
	.reward-heading { display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: start; gap: 12px; }
	.reward-title {
		margin: 0;
		display: -webkit-box;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		overflow: hidden;
		overflow-wrap: anywhere;
		line-height: 1.3;
	}
	h3.reward-title { font-size: 1.1rem; }
	.reward-cost { color: var(--accent); white-space: nowrap; line-height: 1.3; }
</style>
