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
