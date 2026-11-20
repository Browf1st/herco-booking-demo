<script lang="ts">
	import { finishes } from '../shared/coating';
	import { wheels } from '../shared/bookingCatalog';
	import { appointmentPowderParts, appointmentWheelSizes, type CoatingDraft } from './booking-coating';

	let { options = $bindable(), ceramic, powder, disabled }: {
		options: CoatingDraft;
		ceramic: boolean;
		powder: boolean;
		disabled: boolean;
	} = $props();
</script>

<fieldset class="stack" {disabled}>
	<legend>Coating details</legend>
	<p class="small muted">The shop uses these details to price your request. See the estimate below before submitting.</p>
	{#if ceramic}
		<label>Ceramic finish
			<select bind:value={options.ceramic}>
				<option value="">Discuss with the shop</option>
				{#each finishes as finish (finish)}
					<option value={finish}>{finish}{finish === 'Enhance' ? ' (red Honda ADV / PCX)' : ''}</option>
				{/each}
			</select>
		</label>
		{#if options.ceramic === 'Enhance'}
			<label class="choice"><input type="checkbox" bind:checked={options.red} required /> My Honda ADV or PCX 150/160 is red</label>
		{/if}
	{/if}
	{#if powder}
		<fieldset class="stack">
			<legend>Parts for powder coating</legend>
			<div class="cols">
				{#each appointmentPowderParts as part (part)}
					<label class="choice"><input type="checkbox" value={part} bind:group={options.powder} /> {part}</label>
				{/each}
			</div>
		</fieldset>
		{#if options.powder.includes(wheels)}
			<div class="cols">
				<label>Front mag diameter (inches)
					<select bind:value={options.front}>
						<option value="">No front mag</option>
						{#each appointmentWheelSizes as size (size)}<option>{size}</option>{/each}
					</select>
				</label>
				<label>Rear mag diameter (inches)
					<select bind:value={options.rear}>
						<option value="">No rear mag</option>
						{#each appointmentWheelSizes as size (size)}<option>{size}</option>{/each}
					</select>
				</label>
			</div>
		{/if}
	{/if}
</fieldset>

<style>
	fieldset { border: 1px solid var(--line); border-radius: 8px; min-width: 0; }
	legend { font-weight: 700; }
	.choice { display: flex; align-items: center; gap: .5rem; }
	.choice input { width: auto; }
</style>
