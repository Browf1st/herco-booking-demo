<script lang="ts">
	import type { CoatingOptions } from './booking-coating';
	let { options }: { options?: CoatingOptions | null } = $props();
	import { powderCategoryLabels, powderSizeLabels, type PowderCategory } from '../shared/bookingCatalog';
	import { powderSizeFromValue } from '../shared/powderPricing';
	/** New bookings store a size key; old ones store a label, which is shown as saved. */
	const wheelSize = (value: string) => { const size = powderSizeFromValue(value); return size && value === size ? powderSizeLabels[size] : value; };
	const sizeLabel =(value?: string) => !value ? 'None selected' : value === 'Not sure' ? value : value + ' inches';
</script>

{#if options?.ceramic_finish || options?.powder_parts?.length}
	<div>
		<strong>Original coating details</strong>
		{#if options.ceramic_finish}<p>Ceramic finish · {options.ceramic_finish}</p>{/if}
		{#if options.powder_parts?.length}<p>Powder coating · {options.powder_parts.join(', ')}</p>{/if}
		{#if options.wheel_front || options.wheel_rear}
			<p>Front mag · {sizeLabel(options.wheel_front)}</p>
			<p>Rear mag · {sizeLabel(options.wheel_rear)}</p>
		{/if}
	</div>
{/if}
{#if options?.ui_catalog}
 <div>
  {#if options.ui_catalog.model_year}<p>Model year · {options.ui_catalog.model_year}</p>{/if}
  {#if options.ui_catalog.ceramic_addons?.length}<p>Ceramic add-ons · {options.ui_catalog.ceramic_addons.join(', ')}</p>{/if}
  {#if options.ui_catalog.wheel_type}<p>Mags · {wheelSize(options.ui_catalog.wheel_type)}{options.ui_catalog.prismatic?' · Prismatic':''}</p>{/if}
  {#if options.ui_catalog.powder_category}<p>Color group · {powderCategoryLabels[options.ui_catalog.powder_category as PowderCategory] ?? options.ui_catalog.powder_category}</p>{/if}
  {#if options.ui_catalog.custom_note}<p class="notes">Custom finish idea · {options.ui_catalog.custom_note}</p>{/if}
  {#if options.ui_catalog.wheel_extras?.length}<p>Wheel extras · {options.ui_catalog.wheel_extras.join(', ')}</p>{/if}
  {#if options.ui_catalog.finish}<p>Preferred color · {options.ui_catalog.finish}</p>{/if}
  {#if options.ui_catalog.notes}<p class="notes">Notes for the shop · {options.ui_catalog.notes}</p>{/if}
 </div>
{/if}
<style>.notes{white-space:pre-wrap}</style>
