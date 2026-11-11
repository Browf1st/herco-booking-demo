<script lang="ts">
 import { finishes, modelAdjustment, motorcycleOptions, parts, type Pricing } from './coating';
 import { sizes, type Size } from './config';
 import { db, updatePricing } from './store.svelte';
 let draft = $state<Pricing>($state.snapshot(db.pricing));
 let model = $state('');
 let adjustment = $state<number | undefined>();
 let message = $state('');
 let error = $state('');
 const models = (Object.keys(sizes) as Size[]).flatMap(motorcycleOptions).toSorted();
 function save(event: SubmitEvent) {
  event.preventDefault();
  try {
   const pricing = $state.snapshot(draft);
   if (model) pricing.models[model] = adjustment ?? 0;
   updatePricing(pricing);
   draft = $state.snapshot(db.pricing);
   message = 'Prices saved. New and edited bookings use these prices.';
   error = '';
  } catch (e) { error = (e as Error).message; message = ''; }
 }
</script>
<form class="card stack" onsubmit={save}>
 <h3>Service prices and promotion</h3>
 <p class="muted">Demo prices in Philippine pesos. Saved estimates stay with existing bookings until their services are edited.</p>
 <label>Promotion discount (%)<input type="number" min="0" max="100" step="0.01" bind:value={draft.promo} required /></label>
 <details open><summary>Ceramic finish prices</summary><div class="cols">
  {#each finishes as finish}<label>{finish}<input type="number" min="0" step="0.01" bind:value={draft.ceramic[finish]} required /></label>{/each}
 </div></details>
 <details><summary>Powder coating prices by part</summary><div class="cols">
  {#each parts as part}<label>{part}<input type="number" min="0" step="0.01" bind:value={draft.powder[part]} required /></label>{/each}
 </div></details>
 <details><summary>Ceramic motorcycle price adjustments</summary><div class="stack">
  <div class="cols">{#each Object.keys(sizes) as size}<label>{sizes[size as Size]}<input type="number" min="0" step="0.01" bind:value={draft.size[size as Size]} required /></label>{/each}</div>
  <div class="cols">
   <label>Model override<select bind:value={model} onchange={(e) => adjustment = modelAdjustment(draft.models, e.currentTarget.value)}><option value="">Choose a model</option>{#each models as bike}<option>{bike}</option>{/each}</select></label>
   {#if model}<label>Additional charge for {model}<input type="number" min="0" step="0.01" bind:value={adjustment} required /></label>{/if}
  </div>
 </div></details>
 {#if message}<p role="status">{message}</p>{/if}
 {#if error}<p class="error" role="alert">{error}</p>{/if}
 <div><button class="btn">Save pricing</button></div>
</form>
