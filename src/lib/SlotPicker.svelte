<script lang="ts">
	import DayStrip from './DayStrip.svelte';
	import { fmtDate, fmtSlot } from './dates';
	import { slotsFor } from './store.svelte';

	let { date = $bindable(), slot = $bindable() }: { date: string; slot: string } = $props();

	function pick(d: string) {
		date = d;
		slot = '';
	}
</script>

<DayStrip value={date} onpick={pick} />
{#if date}
	<p class="muted">Drop-off time on {fmtDate(date)}</p>
	<div class="slots">
		{#each slotsFor(date) as s (s.time)}
			<button type="button" class="opt" class:on={slot === s.time} disabled={!s.free} onclick={() => (slot = s.time)}>
				<b>{fmtSlot(s.time)}</b>
				<span class="small muted">{s.free ? 'Open' : 'Taken'}</span>
			</button>
		{/each}
	</div>
{:else}
	<p class="muted">Pick a date to see the open slots.</p>
{/if}

<style>
	.slots {
		display: grid;
		gap: 8px;
		grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
	}

	button:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}
</style>
