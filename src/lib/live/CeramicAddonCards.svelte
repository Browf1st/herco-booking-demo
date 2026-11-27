<script lang="ts">
	let { addons, selected = $bindable(), priceText, note = '' }: {
		/** Add-on names, in the order to show. */
		addons: string[];
		/** The chosen add-on names. Any number can be picked. */
		selected: string[];
		/** Text for one add-on's price (already says "Shop quote" when it cannot be priced). */
		priceText: (addon: string) => string;
		note?: string;
	} = $props();

	/** One small line icon per add-on. Unknown names get the sparkle. */
	const icons: Record<string, string> = {
		'Matte to Glossy': 'M12 3v2m0 14v2M3 12h2m14 0h2M6 6l1.4 1.4m9.2 9.2L18 18M6 18l1.4-1.4m9.2-9.2L18 6M12 8l1.2 2.8L16 12l-2.8 1.2L12 16l-1.2-2.8L8 12l2.8-1.2z',
		'Inner coating': 'M4 8l8-5 8 5v8l-8 5-8-5zM12 3v18M4 8l8 5 8-5',
		'Graphene coating': 'M12 3l7 4v6l-7 4-7-4V7zM12 17v4M5 13l-2 3m18-3l-2 3'
	};
	const fallback = 'M12 2l2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5z';
</script>

<fieldset class="stack"><legend>Optional add-ons <span class="hint">pick any</span></legend>
	<div class="cards">
		{#each addons as addon (addon)}
			<label class="card" class:picked={selected.includes(addon)}>
				<input type="checkbox" value={addon} bind:group={selected} />
				<span class="icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d={icons[addon] ?? fallback} /></svg></span>
				<span class="name">{addon}</span>
				<strong class="price">{priceText(addon)}</strong>
			</label>
		{/each}
	</div>
	{#if note}<p class="small muted">{note}</p>{/if}
</fieldset>

<style>
	fieldset { min-inline-size: 0; margin: 0; padding: 0; border: 0; }
	legend { margin-bottom: 10px; padding: 0; color: var(--muted); font-size: .82rem; font-weight: 750; letter-spacing: .05em; text-transform: uppercase; }
	.hint { margin-inline-start: 6px; font-weight: 500; letter-spacing: 0; text-transform: none; }
	.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 170px), 1fr)); gap: 8px; }
	.card { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: 4px 10px; align-items: center; position: relative; min-block-size: 44px; padding: 12px 38px 12px 12px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); color: var(--text); cursor: pointer; }
	.card input { position: absolute; inset-inline-end: 12px; inset-block-start: 12px; inline-size: 1.1rem; block-size: 1.1rem; margin: 0; accent-color: var(--accent); }
	.card:hover { background: var(--panel-2); }
	.card.picked { border-color: var(--accent); box-shadow: inset 0 0 0 1px var(--accent); }
	.card:has(:focus-visible) { outline: 2px solid var(--accent); outline-offset: 2px; }
	.icon { display: inline-grid; place-items: center; inline-size: 2rem; block-size: 2rem; border-radius: 7px; color: var(--accent); background: color-mix(in srgb, var(--accent) 9%, var(--panel)); }
	.icon svg { inline-size: 1.1rem; block-size: 1.1rem; }
	.name { font-weight: 650; overflow-wrap: anywhere; }
	.price { grid-column: 2; color: var(--muted); font-size: .9rem; }
</style>
