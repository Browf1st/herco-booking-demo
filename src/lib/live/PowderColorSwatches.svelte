<script lang="ts">
	import { resolve } from '$app/paths';
	import type { PowderColorEntry } from '../shared/powderPricing';

	let { entries, selectedId, priceText, label, onpick }: {
		entries: PowderColorEntry[]; selectedId: string; label: string;
		/** Short price text under a colour name (empty when no price applies yet). */
		priceText: (entry: PowderColorEntry) => string;
		onpick: (entry: PowderColorEntry) => void;
	} = $props();

	let brokenPhotos = $state<string[]>([]);
	const groupName = $props.id();
	const photoUrl = (entry: PowderColorEntry) => resolve('/api/pricing/color-photo') + '?entry=' + encodeURIComponent(entry.id);
	const showPhoto = (entry: PowderColorEntry) => Boolean(entry.photoPath) && !brokenPhotos.includes(entry.id);
</script>

{#if entries.length}
	<div class="swatches" role="radiogroup" aria-label={label}>
		{#each entries as entry (entry.id)}
			<label class="swatch" class:picked={selectedId === entry.id}>
				<input type="radio" name={groupName} checked={selectedId === entry.id} onchange={() => onpick(entry)} />
				{#if showPhoto(entry)}
					<img src={photoUrl(entry)} alt="" loading="lazy" decoding="async" width="120" height="120"
						onerror={() => brokenPhotos = [...brokenPhotos, entry.id]} />
				{:else}
					<span class="no-photo" aria-hidden="true">{entry.name.trim().slice(0, 2).toUpperCase()}</span>
				{/if}
				<span class="name">{entry.name}</span>
				{#if priceText(entry)}<span class="price">{priceText(entry)}</span>{/if}
			</label>
		{/each}
	</div>
{:else}
	<p class="small muted">No colours are listed in this group yet. Pick another group, or tell the shop in your notes.</p>
{/if}

<style>
	.swatches { display: grid; grid-template-columns: repeat(auto-fill, minmax(96px, 1fr)); gap: 8px; }
	.swatch { position: relative; display: flex; flex-direction: column; min-block-size: 44px; overflow: hidden; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); color: var(--text); cursor: pointer; }
	.swatch input { position: absolute; inset-block-start: 6px; inset-inline-start: 6px; z-index: 1; inline-size: 1rem; block-size: 1rem; accent-color: var(--accent); }
	.swatch:hover { background: var(--panel-2); }
	.swatch.picked { border-color: var(--accent); box-shadow: inset 0 0 0 1px var(--accent); }
	.swatch:has(:focus-visible) { outline: 2px solid var(--accent); outline-offset: 2px; }
	img, .no-photo { display: block; inline-size: 100%; aspect-ratio: 1; object-fit: cover; }
	.no-photo { display: grid; place-items: center; background: var(--panel-2); color: var(--muted); font-weight: 800; letter-spacing: .05em; }
	.name { padding: 6px 8px 0; font-size: .85rem; font-weight: 650; overflow-wrap: anywhere; }
	.price { padding: 0 8px 6px; color: var(--muted); font-size: .78rem; }
	.name:last-child { padding-block-end: 6px; }
</style>
