<script lang="ts">
	import { customNoteLimit, powderCategoryLabels, powderSizeLabels, powderSizes, type PowderCategory, type PowderSize } from '../shared/bookingCatalog';
	import { effectivePowderSize, powderSizeFromValue, wheelRate, type PowderColorEntry, type PowderModel } from '../shared/powderPricing';
	import { money, type Selection } from '../shared/coating';
	import PowderColorSwatches from './PowderColorSwatches.svelte';

	let { value = $bindable(), model, bike, withMags, estimate }: {
		value: Selection; model: PowderModel; bike: string;
		/** Wheels are chosen: a size is needed and prices can be shown. */
		withMags: boolean;
		/** Text for the running wheel price (already says "Shop quote required" when it cannot be priced). */
		estimate: string;
	} = $props();

	const options = $derived(value.catalog!);
	const size = $derived(powderSizeFromValue(options.wheelType));
	const category = $derived(options.powderCategory);
	const entries = $derived(category ? model.colorEntries.filter(entry => entry.category === category && entry.enabled !== false) : []);
	const sizeHint: Partial<Record<PowderSize, string>> = { 'not-sure': 'Ask for a quote' };
	const categoryNames = $derived(model.categories.length ? model.categories : (Object.keys(powderCategoryLabels) as PowderCategory[]));
	// The size the shop really prices this bike at (same rule as the estimate and the server).
	const priceSize = $derived(effectivePowderSize(model, bike, size));
	const tiered = $derived(withMags && !!size && priceSize !== size && priceSize !== '');
	const priced = $derived(withMags && size !== '' && size !== 'not-sure');

	function chooseSize(next: PowderSize) { options.wheelType = next; }
	function chooseCategory(next: PowderCategory) {
		if (options.powderCategory === next) return;
		options.powderCategory = next;
		options.prismatic = false;
		options.colorId = '';
		value.finish = '';
	}
	function chooseColor(entry: PowderColorEntry) { options.colorId = entry.id; value.finish = entry.name; }
	function clearColor() { options.colorId = ''; value.finish = ''; }
	function categoryPrice(next: PowderCategory) {
		if (next === 'custom') return 'Shop quote';
		const amount = priceSize && priceSize !== 'not-sure' ? model.baseTable[next]?.[priceSize] : null;
		return typeof amount === 'number' ? 'From ' + money(amount) : '';
	}
	function swatchPrice(entry: PowderColorEntry) {
		if (!withMags || entry.category === 'custom' || !priceSize) return '';
		const amount = wheelRate(model, { bike, size, finish: entry.name });
		return amount === undefined ? 'Shop quote' : money(amount);
	}
</script>

<div class="stack">
	{#if withMags}
		<fieldset class="stack"><legend>1. Mag size</legend>
			<div class="cards">
				{#each powderSizes as option (option)}
					<label class="card" class:picked={size === option}>
						<input type="radio" name="powder-size" checked={size === option} onchange={() => chooseSize(option)} />
						<strong>{powderSizeLabels[option]}</strong>
						{#if sizeHint[option]}<span class="small muted">{sizeHint[option]}</span>{/if}
					</label>
				{/each}
			</div>
			{#if !size}<p class="small muted">Choose a size, or Not sure and the shop will quote.</p>{/if}
			{#if tiered && priceSize}<p class="small muted">The shop prices your bike at {powderSizeLabels[priceSize]}, so prices below use that size.</p>{/if}
		</fieldset>
	{/if}

	<fieldset class="stack"><legend>{withMags ? '2.' : '1.'} Color group</legend>
		<div class="cards">
			{#each categoryNames as option (option)}
				<label class="card" class:picked={category === option}>
					<input type="radio" name="powder-category" checked={category === option} onchange={() => chooseCategory(option)} />
					<strong>{powderCategoryLabels[option]}</strong>
					{#if categoryPrice(option)}<span class="small muted">{categoryPrice(option)}</span>{/if}
				</label>
			{/each}
		</div>
	</fieldset>

	{#if category === 'custom'}
		<div class="stack custom">
			<p><strong>The shop will quote this.</strong> Custom and two-tone finishes have no fixed price. The shop reviews your request and sends a quote before any work starts.</p>
			<p class="small muted">Examples from the shop (optional, tap one you like):</p>
			<PowderColorSwatches {entries} selectedId={options.colorId} label="Custom finish examples" priceText={() => ''} onpick={chooseColor} />
			{#if options.colorId}<button type="button" class="link" onclick={clearColor}>Clear my choice</button>{/if}
			<label>Describe the finish you want (optional)
				<textarea bind:value={options.customNote} maxlength={customNoteLimit} rows="3" placeholder="e.g. Black wheels with gold lips"></textarea>
				<span class="small muted">{options.customNote.length}/{customNoteLimit}</span>
			</label>
		</div>
	{:else if category}
		<fieldset class="stack"><legend>{withMags ? '3.' : '2.'} Pick a color</legend>
			<PowderColorSwatches {entries} selectedId={options.colorId} label={powderCategoryLabels[category] + ' colors'} priceText={swatchPrice} onpick={chooseColor} />
		</fieldset>
	{:else}
		<p class="small muted">Choose a color group to see the colors.</p>
	{/if}

	{#if withMags}
		<p class="estimate" aria-live="polite"><span>Mags estimate</span>
			<strong>{category === 'custom' ? 'Shop quote required' : !value.finish.trim() && priced ? 'Pick a color to see the price' : estimate}</strong>
		</p>
	{/if}
</div>

<style>
	fieldset { min-inline-size: 0; margin: 0; border: 1px solid var(--line); border-radius: 6px; }
	.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 130px), 1fr)); gap: 8px; }
	.card { display: flex; flex-direction: column; gap: 2px; min-block-size: 44px; padding: 10px 10px 10px 34px; position: relative; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); color: var(--text); cursor: pointer; }
	.card input { position: absolute; inset-inline-start: 10px; inset-block-start: 12px; accent-color: var(--accent); }
	.card:hover { background: var(--panel-2); }
	.card.picked { border-color: var(--accent); box-shadow: inset 0 0 0 1px var(--accent); }
	.card:has(:focus-visible) { outline: 2px solid var(--accent); outline-offset: 2px; }
	.custom { padding: 10px; border: 1px dashed var(--line); border-radius: 8px; }
	.link { align-self: flex-start; min-block-size: 44px; padding: 0 4px; border: 0; background: none; color: var(--accent); font: inherit; text-decoration: underline; cursor: pointer; }
	.estimate { display: flex; justify-content: space-between; gap: 12px; margin: 0; padding: 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--panel-2); }
	textarea { inline-size: 100%; }
</style>
