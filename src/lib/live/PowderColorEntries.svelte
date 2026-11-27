<script lang="ts">
	import { resolve } from '$app/paths';
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import {
		powderCategories, powderCategoryLabels, powderSizeLabels, pricedPowderSizes, type PowderCategory, type PowderSize
	} from '../shared/bookingCatalog';
	import { newColorEntry } from './powder-model';
	import type { PowderModel } from './ui-catalog';

	let { model = $bindable(), disabled, savedIds, pending = $bindable(), photoNotes, photoVersion, onphoto }: {
		model: PowderModel; disabled: boolean; savedIds: string[]; pending: Record<string, File>;
		photoNotes: Record<string, string>; photoVersion: Record<string, number>;
		onphoto: (id: string, file: File) => void;
	} = $props();
	let opened = $state<string>('');

	function add() {
		const entry = newColorEntry();
		model.colorEntries.push(entry);
		opened = entry.id;
	}
	function remove(id: string) {
		model.colorEntries = model.colorEntries.filter((entry) => entry.id !== id);
		delete pending[id];
	}
	function changeCategory(id: string, category: PowderCategory) {
		const entry = model.colorEntries.find((item) => item.id === id);
		if (!entry) return;
		entry.category = category;
		if (category === 'custom') { entry.quoteOnly = true; delete entry.pricesBySize; }
	}
	function setOverride(id: string, size: PowderSize, text: string) {
		const entry = model.colorEntries.find((item) => item.id === id);
		if (!entry) return;
		const prices = { ...(entry.pricesBySize ?? {}) };
		if (text === '') delete prices[size]; else prices[size] = Number(text);
		entry.pricesBySize = prices;
	}
	function pick(id: string, event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		if (file) onphoto(id, file);
		input.value = '';
	}
	const photoUrl = (id: string) => resolve('/api/pricing/color-photo') + '?entry=' + encodeURIComponent(id) + '&v=' + (photoVersion[id] ?? 0);
</script>

<fieldset class="stack" {disabled}>
	<legend>Powder colours</legend>
	<p class="small muted">Each colour has a type that sets its price. Add a price for a size only if this colour differs from its type.</p>
	{#each model.colorEntries as entry (entry.id)}
		{@const locked = entry.category === 'custom'}
		<details class="entry" class:off={entry.enabled === false} open={opened === entry.id}>
			<summary>
				<span class="swatch" aria-hidden="true">
					{#if entry.photoPath}<img src={photoUrl(entry.id)} alt="" loading="lazy" width="32" height="32" />{/if}
				</span>
				<strong>{entry.name || 'New colour'}</strong>
				<span class="chip">{powderCategoryLabels[entry.category]}</span>
				{#if entry.quoteOnly}<span class="chip">Quote</span>{/if}
				{#if entry.enabled === false}<span class="chip">Off</span>{/if}
			</summary>
			<div class="stack body">
				<div class="cols">
					<label>Colour name<input bind:value={entry.name} maxlength="80" required /></label>
					<label>Colour type
						<select value={entry.category} onchange={(event) => changeCategory(entry.id, event.currentTarget.value as PowderCategory)}>
							{#each powderCategories as category (category)}<option value={category}>{powderCategoryLabels[category]}</option>{/each}
						</select>
					</label>
				</div>
				<label class="check">
					<input type="checkbox" checked={entry.enabled !== false} onchange={(event) => (entry.enabled = event.currentTarget.checked)} />
					Enabled (customers can pick this colour)
				</label>
				<label class="check">
					<input type="checkbox" bind:checked={entry.quoteOnly} disabled={locked} />
					Shop quote only {locked ? '(always on for Custom)' : ''}
				</label>
				{#if !locked && !entry.quoteOnly}
					<div class="stack">
						<p class="small muted">Optional price for this colour (₱). Leave blank to use the colour type price.</p>
						<div class="cols">
							{#each pricedPowderSizes as size (size)}
								<label>{powderSizeLabels[size]}
									<input type="number" min="0" max="21474836.47" step=".01" placeholder="Type price"
										value={entry.pricesBySize?.[size] ?? ''} oninput={(event) => setOverride(entry.id, size, event.currentTarget.value)} />
								</label>
							{/each}
						</div>
					</div>
				{/if}
				<div class="stack photo">
					<strong>Colour photo</strong>
					<div class="row">
						<span class="swatch big" role="img" aria-label={entry.photoPath ? entry.name + ' photo' : 'No photo yet'}>
							{#if entry.photoPath}<img src={photoUrl(entry.id)} alt="" loading="lazy" width="64" height="64" />{:else}<span>No photo</span>{/if}
						</span>
						<label class="btn sm ghost upload">
							<ActionIcon name="out" />{entry.photoPath ? 'Replace photo' : 'Add photo'}
							<input type="file" accept="image/jpeg,image/png,image/webp" onchange={(event) => pick(entry.id, event)} />
						</label>
					</div>
					{#if pending[entry.id]}<p class="small" role="status">{pending[entry.id].name} will upload right after you save.</p>{/if}
					{#if photoNotes[entry.id]}<p class="small" role="status">{photoNotes[entry.id]}</p>{/if}
					{#if !savedIds.includes(entry.id)}<p class="small muted">Save this colour first. The photo uploads after the save.</p>{/if}
				</div>
				<div><button type="button" class="btn sm ghost" onclick={() => remove(entry.id)}><ActionIcon name="close" />Remove colour</button></div>
			</div>
		</details>
	{:else}
		<p>No colours yet. Add one to start.</p>
	{/each}
	<div><button type="button" class="btn sm" onclick={add}><ActionIcon name="add" />Add colour</button></div>
</fieldset>

<style>
	.entry { border: 1px solid var(--line); border-radius: .4rem; padding: .25rem .75rem; }
	.entry.off summary { opacity: .6; }
	summary { display: flex; flex-wrap: wrap; align-items: center; gap: .5rem; min-block-size: 2.75rem; cursor: pointer; }
	.body { padding-block: .5rem; }
	.chip { padding: .1rem .55rem; border: 1px solid var(--line); border-radius: 999px; font-size: .8rem; }
	.swatch { display: inline-grid; place-items: center; inline-size: 2rem; block-size: 2rem; border: 1px solid var(--line); border-radius: .3rem; overflow: hidden; font-size: .7rem; }
	.swatch.big { inline-size: 4rem; block-size: 4rem; text-align: center; }
	.swatch img { inline-size: 100%; block-size: 100%; object-fit: cover; }
	.check { display: flex; align-items: center; gap: .5rem; }
	.check input { inline-size: auto; }
	.upload { position: relative; cursor: pointer; }
	.upload input { position: absolute; inset: 0; opacity: 0; cursor: pointer; inline-size: 100%; }
	.upload:focus-within { outline: 2px solid currentColor; outline-offset: 2px; }
</style>
