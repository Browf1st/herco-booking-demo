<script lang="ts">
	import { powderCategories, powderCategoryLabels, powderSizes, powderSizeLabels } from '../shared/bookingCatalog';
	import type { PowderModel } from './ui-catalog';

	let { model = $bindable(), disabled }: { model: PowderModel; disabled: boolean } = $props();
</script>

<fieldset class="stack" {disabled}>
	<legend>Powder base prices (₱)</legend>
	<p class="small muted">One price per colour type and wheel size. Custom colours and "Not sure" sizes are always a shop quote.</p>
	<div class="grid-scroll">
		<table>
			<thead>
				<tr>
					<th scope="col">Colour type</th>
					{#each powderSizes as size (size)}<th scope="col">{powderSizeLabels[size]}</th>{/each}
				</tr>
			</thead>
			<tbody>
				{#each powderCategories as category (category)}
					<tr>
						<th scope="row">{powderCategoryLabels[category]}</th>
						{#each powderSizes as size (size)}
							<td>
								{#if category === 'custom' || size === 'not-sure'}
									<span class="quote">Quote</span>
								{:else}
									<input type="number" min="0" max="21474836.47" step=".01" required
										aria-label={powderCategoryLabels[category] + ' price, ' + powderSizeLabels[size]}
										bind:value={model.baseTable[category][size]} />
								{/if}
							</td>
						{/each}
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
</fieldset>

<style>
	.grid-scroll { overflow-x: auto; }
	table { border-collapse: collapse; inline-size: 100%; min-inline-size: 28rem; }
	th, td { padding: .35rem; text-align: start; }
	thead th { font-size: .85rem; }
	td input { inline-size: 100%; min-block-size: 2.75rem; }
	.quote { display: inline-block; padding: .2rem .6rem; border: 1px dashed var(--line); border-radius: 999px; font-size: .85rem; }
</style>
