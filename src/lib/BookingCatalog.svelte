<script lang="ts">
 import { asset } from '$app/paths';
 import type { Snippet } from 'svelte';
 import { basicColors, catalogItems, ceramicAddons, powderParts, powderPhotos, wheelExtras, wheelRates, wheels } from './bookingCatalog';
 import { linePrice, money, type Selection } from './coating';

 let { value = $bindable(), bike, year, serviceControls = true, powderDetails }: { value: Selection; bike: string; year?: number; serviceControls?: boolean; powderDetails?: Snippet } = $props();
 let showSmallParts = $state(false);
 const hasMags = $derived(value.powderParts.includes(wheels));
 const showParts = $derived(showSmallParts || value.powderParts.some(part => part !== wheels));
 const options = $derived(value.catalog!);
 const allOptions = $derived(catalogItems(
  { ...value, ceramic: true, powder: true, powderParts: Object.keys(powderParts), finish: '' },
  { ...options, ceramicAddons: Object.keys(ceramicAddons) }, bike, year
 ));

 function price(label: string) {
  const range = allOptions.get(label);
  return linePrice({ label, subtotal: range?.[0] ?? 0, discount: 0, maximum: range && range[0] !== range[1] ? range[1] : undefined, pending: !range });
 }
</script>

<div class="stack">
 {#if serviceControls || value.ceramic}
 <div class="primary stack" class:selected={value.ceramic}>
 <div class="package-header">
 {#if serviceControls}
  <label class="option"><input type="checkbox" bind:checked={value.ceramic} /> Ceramic coating</label>
 {:else}
  <div class="package-title"><h3>Ceramic Coating</h3><span class="flagship">Flagship protection</span></div>
 {/if}
 <strong class="package-price">{price('Ceramic coating')}</strong>
 {#if value.ceramic}
  <div class="package-meta small muted">
   <span><b aria-hidden="true">◷</b> {allOptions.get('Ceramic coating')?.[0] === 1999 ? '3–4 hours' : '2–3 hours'} turnover</span>
   <span>Wait at the shop or pick up later</span>
   <strong>2–5 years with proper care</strong>
  </div>
 {/if}
 </div>
 {#if value.ceramic}
  <div class="package-body stack">
   <div class="package-caption"><h4>3-stage detailing &amp; protection</h4><span>All included</span></div>
   <div class="package-stages">
    <div class="package-stage">
     <div class="stage-top"><span aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2l2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5z"/></svg></span><strong>Surface prep</strong></div>
     <h4>Stage 1: Deep Prep &amp; Decontamination</h4>
     <ul><li>Premium motorwash</li><li>Paint decontamination</li><li>Three-step detailing</li><li>Removal of swirl marks and light hairline scratches</li></ul>
    </div>
    <div class="package-stage">
     <div class="stage-top"><span aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3l8 4v5c0 4-4 7-8 9-4-2-8-5-8-9V7z M8 12l3 3 5-5"/></svg></span><strong>Full coverage</strong></div>
     <h4>Stage 2: 3-Layer HERCO Shield</h4>
     <p class="small muted">Ceramic coating applied to:</p>
     <ul class="coverage"><li>Outer fairings</li><li>Headlights</li><li>Signal and brake lights</li><li>Windshield or visor</li></ul>
    </div>
    <div class="package-stage">
     <div class="stage-top"><span aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M9 3h6m-5 0v7l-6 8a2 2 0 001.6 3h12.8a2 2 0 001.6-3l-6-8V3M7 15h10"/></svg></span><strong>Long-term results</strong></div>
     <h4>Stage 3: Hydrophobic Protection &amp; Finish</h4>
     <ul><li>Hydrophobic paint protection</li><li>Improved scratch resistance</li><li>Deeper gloss and easier cleaning</li></ul>
    </div>
   </div>
   <p class="package-note small"><span aria-hidden="true">i</span><span><strong>Expected durability</strong> · 2–5 years with proper care and maintenance.</span></p>
  </div>
 {/if}
 </div>
 {/if}
 {#if value.ceramic}
  <fieldset class="stack ceramic-addons"><legend>Optional ceramic add-ons</legend>
   <div class="add-ons">
   {#each Object.keys(ceramicAddons) as addon}
    <label class="addon-card"><input type="checkbox" value={addon} bind:group={options.ceramicAddons} /><span>{addon}</span><strong>{price(addon)}</strong></label>
   {/each}
   </div>
   {#if options.bigBike}<p class="small muted">The shop will confirm any big-bike add-on price adjustments.</p>{/if}
  </fieldset>
 {/if}
 {#if serviceControls}<label class="option"><input type="checkbox" bind:checked={value.powder} /> Powder coating</label>{/if}
 {#if value.powder}
  <p>Allow 8–12 hours · Wednesday, Saturday, and Sunday.</p>
  <fieldset class="stack"><legend>What would you like powder coated?</legend>
   <div class="add-ons">
    <label class="option"><input type="checkbox" value={wheels} bind:group={value.powderParts} /> Mags (wheels)</label>
    <label class="option"><input type="checkbox" checked={showParts} onchange={(event) => {
     showSmallParts = event.currentTarget.checked;
     if (!showSmallParts) value.powderParts = value.powderParts.filter(part => part === wheels);
    }} /> Small parts</label>
   </div>
   {#if hasMags || showParts}{@render powderDetails?.()}{/if}
   {#if value.powderParts.includes(wheels)}
    <fieldset class="stack"><legend>Choose your mags</legend>
     {#each Object.entries(wheelRates) as [type, [low, high]]}
      <label class="wheel-rate">
       <input type="radio" name="wheel-category" value={type} bind:group={options.wheelType} required />
       <span><strong>{type}</strong><span>{money(low)}–{money(high)} depending on color</span>
        {#if type.startsWith('10')}<span>Prismatic · ₱2,999</span>
        {:else if type.startsWith('17')}<span>Prismatic · ₱3,999</span>{/if}
       </span>
      </label>
     {/each}
     <label class="option"><input type="radio" name="wheel-category" value="Not sure" bind:group={options.wheelType} /> Not sure · Ask for a quote</label>
    </fieldset>
    {#if options.wheelType}
     <label class="option"><input type="checkbox" bind:checked={options.prismatic} /> Request a prismatic color
      <strong>{options.wheelType.startsWith('10') ? '₱2,999' : options.wheelType.startsWith('17') ? '₱3,999' : 'Shop quote'}</strong>
     </label>
    {/if}
    {#each wheelExtras as extra}
     <label class="option"><input type="checkbox" value={extra} bind:group={options.wheelExtras} /> {extra} <strong>₱499</strong></label>
    {/each}
   {/if}
   {#if showParts}
    <strong>Choose small parts</strong>
    <p>Bring detached parts. Small parts have no warranty. Walk-ins are Wednesday, Saturday, and Sunday, 9 AM to noon.</p>
    {#each Object.keys(powderParts) as part}
     <label class="option"><input type="checkbox" value={part} bind:group={value.powderParts} /> {part} <strong>{price(part)}</strong></label>
    {/each}
   {/if}
  </fieldset>
  {#if hasMags || showParts}
  <label>Preferred powder color or finish
   <input bind:value={value.finish} maxlength="100" list="powder-colors" placeholder="Choose or type a color" />
   <datalist id="powder-colors">
    {#each basicColors as color}<option value={color}></option>{/each}
    {#each powderPhotos as photo}<option value={photo.name}></option>{/each}
   </datalist>
  </label>
  <p class="small muted">Basic colors: {basicColors.join(', ')}. The photos below show special colors. The shop confirms the final quote.</p>
  <div class="gallery">
   {#each powderPhotos as photo}
    <button type="button" aria-pressed={value.finish === photo.name} onclick={() => value.finish = photo.name}>
     <img src={asset(photo.file)} alt="" loading="lazy" />
     <span>{photo.name}</span>
    </button>
   {/each}
  </div>
  {/if}
 {/if}
</div>

<style>
 fieldset { min-inline-size: 0; margin: 0; border: 1px solid var(--line); border-radius: 6px; }
 .option { display: flex; align-items: center; gap: 8px; padding: 8px; }
 .option strong { margin-inline-start: auto; text-align: right; }
 .wheel-rate { display: flex; align-items: flex-start; gap: 10px; padding: 10px; border: 1px solid var(--line); border-radius: 6px; background: var(--bg); cursor: pointer; }
 .wheel-rate:has(:checked) { border-color: var(--accent); }
 .wheel-rate input { flex: none; accent-color: var(--accent); }
 .wheel-rate span { display: block; }
 .primary { gap: 0; overflow: hidden; border: 1px solid var(--line); border-radius: 14px; background: var(--panel); }
 .package-header { display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: start; gap: 6px 12px; padding: clamp(16px, 2vw, 24px); background: var(--ceramic-package-bg, var(--bg)); }
 .package-title, .package-meta, .stage-top, .package-caption { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 10px; }
 .flagship { padding: 2px 8px; border-radius: 99px; color: var(--accent-ink); background: var(--accent); font-size: .63rem; font-weight: 800; text-transform: uppercase; }
 .package-meta { grid-column: 1 / -1; }
 .package-meta b, .package-caption span { color: var(--accent); }
 .package-meta strong { color: var(--ok); }
 .package-header h3 { font: 750 1.2rem var(--body); text-transform: none; }
 .package-price { color: var(--accent); font-size: clamp(1rem, 3vw, 1.5rem); font-style: italic; font-weight: 900; text-align: right; }
 .package-body { padding: clamp(16px, 2vw, 24px); border-top: 1px solid color-mix(in srgb, var(--accent) 18%, var(--panel)); }
 .package-caption { justify-content: space-between; color: var(--muted); text-transform: uppercase; letter-spacing: .04em; }
 .package-caption span { font-size: .75rem; font-weight: 700; text-transform: none; }
 .package-body h4 { margin: 0; font-size: .95rem; }
 .package-stages { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 165px), 1fr)); gap: 10px; }
 .package-stage { padding: 14px; border: 1px solid var(--line); border-radius: 9px; background: var(--bg); }
 .stage-top { justify-content: space-between; margin-bottom: 10px; }
 .stage-top span, .package-note > span:first-child { display: inline-grid; place-items: center; flex: none; width: 1.8rem; height: 1.8rem; border-radius: 7px; color: var(--accent); background: color-mix(in srgb, var(--accent) 9%, var(--panel)); font-weight: 800; }
 .stage-top strong { padding: 2px 6px; border-radius: 4px; background: var(--panel-2); color: var(--muted); font-size: .62rem; text-transform: uppercase; }
 .package-stage:nth-child(2) .stage-top strong { color: var(--accent); background: #fdf0f0; }
 .package-stage:nth-child(3) .stage-top strong { color: var(--ok); background: #eafbf4; }
 .stage-top svg { width: 1rem; height: 1rem; }
 .package-stage h4 { font-size: .84rem; line-height: 1.4; }
 .package-stage p { margin-top: 6px; font-size: .78rem; }
 .package-stage:first-child li::marker { color: var(--accent); }
 .package-stage:last-child li::marker { content: '✓  '; color: var(--ok); }
 .package-stage ul { margin: 8px 0 0; padding-inline-start: 1.1em; color: var(--muted); font-size: .78rem; line-height: 1.55; }
 .package-stage li + li { margin-top: 4px; }
 .package-stage .coverage { display: flex; flex-wrap: wrap; gap: 5px; padding: 0; list-style: none; }
 .package-stage .coverage li { font-size: .7rem; margin: 0; padding: 1px 6px; border: 1px solid color-mix(in srgb, var(--line) 65%, var(--panel)); border-radius: 5px; background: var(--panel); }
 .package-note { display: flex; align-items: center; gap: 10px; padding: 10px 12px; border: 1px solid color-mix(in srgb, var(--accent) 18%, var(--panel)); border-radius: 8px; background: var(--ceramic-package-bg, var(--bg)); }
 .primary.selected { border-color: var(--accent); }
 .add-ons { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 230px), 1fr)); gap: 8px; }
 .add-ons .option { border: 1px solid var(--line); border-radius: 6px; background: var(--bg); }
 .add-ons .option:has(input:checked) { border-color: var(--accent); }
 .ceramic-addons { border: 0; padding: 0; }
 .ceramic-addons legend { padding: 0; margin-bottom: 10px; color: var(--muted); font-size: .82rem; font-weight: 750; letter-spacing: .05em; text-transform: uppercase; }
 .addon-card { display: grid; grid-template-columns: minmax(0, 1fr) auto; grid-template-rows: 1fr auto; gap: 4px 12px; padding: 14px; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); cursor: pointer; }
 .addon-card input { grid-area: 1 / 2; align-self: start; margin: 2px 0 0; }
 .addon-card span { grid-area: 1 / 1; font-weight: 650; }
 .addon-card strong { grid-column: 1 / -1; color: var(--muted); }
 .addon-card:hover { background: var(--panel-2); }
 .addon-card:has(:checked) { border-color: var(--accent); box-shadow: inset 0 0 0 1px var(--accent); }
 .addon-card:has(:focus-visible) { outline: 2px solid var(--accent); outline-offset: 2px; }
 input[type='checkbox'] { flex: none; accent-color: var(--accent); width: 1rem; height: 1rem; }
 .gallery { display: grid; grid-template-columns: repeat(auto-fit, minmax(110px, 1fr)); gap: 8px; }
 .gallery button { padding: 0; overflow: hidden; background: var(--panel); color: var(--text); border: 1px solid var(--line); border-radius: 6px; font: inherit; cursor: pointer; }
 .gallery button[aria-pressed='true'] { outline: 2px solid var(--accent); }
 .gallery img { display: block; width: 100%; aspect-ratio: 1; object-fit: cover; }
 .gallery span { display: block; padding: 6px; }
</style>
