<script lang="ts">
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { powderSizeLabels, powderSizes, type PowderSize } from '../shared/bookingCatalog';
	import { normaliseKey } from './powder-model';
	import type { PowderModel } from './ui-catalog';

	let { model = $bindable(), disabled }: { model: PowderModel; disabled: boolean } = $props();
	let bike = $state('');
	let size = $state<PowderSize>('10-14');
	let issue = $state('');

	function add() {
		const key = normaliseKey(bike);
		if (!key) { issue = 'Type the bike name first.'; return; }
		model.bikeTiers[key] = size;
		bike = '';
		issue = '';
	}
	function remove(key: string) { delete model.bikeTiers[key]; }
</script>

<fieldset class="stack" {disabled}>
	<legend>Bike wheel sizes</legend>
	<p class="small muted">Pick the wheel size for a bike so customers do not have to. Bike names are saved in lowercase.</p>
	<div class="cols">
		<label>Bike name<input bind:value={bike} maxlength="120" placeholder="e.g. Honda PCX160" /></label>
		<label>Wheel size
			<select bind:value={size}>
				{#each powderSizes as option (option)}<option value={option}>{powderSizeLabels[option]}</option>{/each}
			</select>
		</label>
	</div>
	{#if issue}<p class="small" role="alert">{issue}</p>{/if}
	<div><button type="button" class="btn sm" onclick={add}><ActionIcon name="add" />Add bike</button></div>
	<ul class="list">
		{#each Object.entries(model.bikeTiers) as [key, value] (key)}
			<li class="row between">
				<span><strong>{key}</strong> · {powderSizeLabels[value]}</span>
				<button type="button" class="btn sm ghost" aria-label={'Remove ' + key} onclick={() => remove(key)}><ActionIcon name="close" />Remove</button>
			</li>
		{:else}
			<li>No bikes mapped yet.</li>
		{/each}
	</ul>
</fieldset>

<style>
	.list { list-style: none; margin: 0; padding: 0; }
	.list li { padding-block: .4rem; border-block-start: 1px solid var(--line); }
</style>
