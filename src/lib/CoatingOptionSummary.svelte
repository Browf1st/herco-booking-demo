<script lang="ts">
	import type { CoatingOptions } from './booking-coating';
	let { options }: { options?: CoatingOptions | null } = $props();
	const sizeLabel = (value?: string) => !value ? 'None selected' : value === 'Not sure' ? value : value + ' inches';
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
  {#if options.ui_catalog.wheel_type}<p>Mags · {options.ui_catalog.wheel_type}{options.ui_catalog.prismatic?' · Prismatic':''}</p>{/if}
  {#if options.ui_catalog.wheel_extras?.length}<p>Wheel extras · {options.ui_catalog.wheel_extras.join(', ')}</p>{/if}
  {#if options.ui_catalog.finish}<p>Preferred color · {options.ui_catalog.finish}</p>{/if}
  {#if options.ui_catalog.notes}<p class="notes">Notes for the shop · {options.ui_catalog.notes}</p>{/if}
 </div>
{/if}
<style>.notes{white-space:pre-wrap}</style>
