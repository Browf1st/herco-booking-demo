<script lang="ts">
 import ActionIcon from '#lib/ActionIcon.svelte';
 import { ceramicAddons, ceramicModels, ceramicTierNames, defaultCeramicCatalogPricing, listedCeramicAddons } from './bookingCatalog';
 import { db, updatePricing } from './store.svelte';
 import { canPerform } from './staffAccess.svelte.ts';

 let draft = $state($state.snapshot(db.pricing.ceramicCatalog ?? defaultCeramicCatalogPricing));
 let promo = $state(db.pricing.promo);
 let priceMessage = $state('');
 let priceError = $state('');
 let promoMessage = $state('');
 let promoError = $state('');
 const tiers = (Object.keys(ceramicModels).map(Number) as (keyof typeof ceramicModels)[]);
 const addons = Object.keys(ceramicAddons) as (keyof typeof ceramicAddons)[];

 function savePrices(event: SubmitEvent) {
  event.preventDefault();
  priceError = '';
  priceMessage = '';
  try {
   updatePricing({ ...$state.snapshot(db.pricing), ceramicCatalog: $state.snapshot(draft) }, 'Pricing');
   priceMessage = 'Ceramic coating prices saved.';
  } catch (error) {
   priceError = (error as Error).message;
  }
 }

 function savePromotion(event: SubmitEvent) {
  event.preventDefault();
  promoError = '';
  promoMessage = '';
  try {
   updatePricing({ ...$state.snapshot(db.pricing), promo }, 'Promotion');
   promoMessage = 'Booking promotion saved.';
  } catch (error) {
   promoError = (error as Error).message;
  }
 }
</script>

<form class="card stack" onsubmit={savePrices}>
 <h3>Ceramic coating prices</h3>
 <p class="muted">Amounts are in Philippine pesos before discounts. Saved booking line items keep their quoted prices.</p>
 <fieldset class="stack" disabled={!canPerform('changePricing')}>
  <legend>Motorcycle tiers</legend>
  <div class="cols">
   {#each tiers as tier (tier)}
    <label>{ceramicTierNames[tier]}<input type="number" min="0" step="0.01" bind:value={draft.tiers[tier]} required /></label>
   {/each}
  </div>
 </fieldset>
 <fieldset class="stack" disabled={!canPerform('changePricing')}>
  <legend>Add-on prices</legend>
  <p class="small muted">Matte to Glossy, Inner coating, and Graphene coating use these ranges when the motorcycle has no pricing tier.</p>
  {#each addons as addon (addon)}
   <div class="addon-row">
    <strong>{addon}</strong>
    <label>Minimum<input aria-label={addon + ' minimum price'} type="number" min="0" step="0.01" bind:value={draft.addons[addon][0]} required /></label>
    <label>Maximum<input aria-label={addon + ' maximum price'} type="number" min="0" step="0.01" bind:value={draft.addons[addon][1]} required /></label>
   </div>
  {/each}
 </fieldset>
 <fieldset class="stack" disabled={!canPerform('changePricing')}>
  <legend>Add-on rates for priced tiers</legend>
  <div class="cols">
   {#each listedCeramicAddons as addon (addon)}
    <label>{addon}<input type="number" min="0" step="0.01" bind:value={draft.listedAddons[addon]} required /></label>
   {/each}
   <label>Matte to Glossy · Premium tier or 2026 Honda PCX
    <input type="number" min="0" step="0.01" bind:value={draft.premiumGloss} required />
   </label>
  </div>
 </fieldset>
 {#if priceMessage}<p role="status">{priceMessage}</p>{/if}
 {#if priceError}<p class="error" role="alert">{priceError}</p>{/if}
 {#if canPerform('changePricing')}<div><button class="btn"><ActionIcon name="save" />Save ceramic prices</button></div>{/if}
</form>

<form class="card stack" onsubmit={savePromotion}>
 <h3>Booking promotion</h3>
 <p class="muted">Applies to ceramic and powder coating estimates. Set to 0% to turn it off.</p>
 <label>Discount (%)<input type="number" min="0" max="100" step="0.01" bind:value={promo} required disabled={!canPerform('changePromotions')} /></label>
 {#if promoMessage}<p role="status">{promoMessage}</p>{/if}
 {#if promoError}<p class="error" role="alert">{promoError}</p>{/if}
 {#if canPerform('changePromotions')}<div><button class="btn"><ActionIcon name="save" />Save promotion</button></div>{/if}
</form>

<style>
 fieldset { min-inline-size: 0; border: 1px solid var(--line); border-radius: .4rem; }
 legend { padding-inline: .4rem; font-weight: 700; }
 .addon-row { display: grid; grid-template-columns: minmax(0, 2fr) repeat(2, minmax(0, 1fr)); gap: .6rem; align-items: center; }
 @media (max-width: 560px) {
  .addon-row { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .addon-row strong { grid-column: 1 / -1; }
 }
</style>
