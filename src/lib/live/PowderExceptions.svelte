<script lang="ts">
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { newException } from './powder-model';
	import type { PowderModel } from './ui-catalog';

	let { model = $bindable(), disabled }: { model: PowderModel; disabled: boolean } = $props();
	let opened = $state('');
	const money = new Intl.NumberFormat('en-PH', { currency: 'PHP', style: 'currency' });

	function add() {
		const rule = newException();
		model.exceptions.push(rule);
		opened = rule.id;
	}
	function remove(id: string) { model.exceptions = model.exceptions.filter((rule) => rule.id !== id); }
	function setPrice(id: string, text: string) {
		const rule = model.exceptions.find((item) => item.id === id);
		if (!rule) return;
		if (text === '') delete rule.priceCentavos; else rule.priceCentavos = Math.round(Number(text) * 100);
	}
	function setQuote(id: string, quote: boolean) {
		const rule = model.exceptions.find((item) => item.id === id);
		if (!rule) return;
		rule.quoteOnly = quote;
		if (quote) delete rule.priceCentavos;
	}
</script>

<fieldset class="stack" {disabled}>
	<legend>Price exceptions</legend>
	<p class="small muted">A special price for one bike: a wheel colour finish, or the ceramic coating. An exception beats the normal price. Turn it off to stop using it.</p>
	<datalist id="powder-colour-names">{#each model.colorEntries as entry (entry.id)}<option value={entry.name}></option>{/each}</datalist>
	{#each model.exceptions as rule (rule.id)}
		<details class="entry" open={opened === rule.id}>
			<summary>
				<strong>{rule.bikeKey || 'New exception'}</strong>
				<span class="chip">{rule.service === 'ceramic' ? 'Ceramic' : 'Wheel colour'}</span>
				<span class="muted">{rule.service === 'ceramic' ? '' : rule.finish}</span>
				<span class="chip">{rule.quoteOnly ? 'Quote' : rule.priceCentavos === undefined ? 'No price' : money.format(rule.priceCentavos / 100)}</span>
				<span class="chip">{rule.enabled ? 'On' : 'Off'}</span>
			</summary>
			<div class="stack body">
				<label>Service
					<select bind:value={rule.service}>
						<option value="wheel-colour">Wheel colour</option>
						<option value="ceramic">Ceramic</option>
					</select>
				</label>
				<label>Bike name<input bind:value={rule.bikeKey} maxlength="120" required placeholder="e.g. Honda PCX160" /></label>
				{#if rule.service === 'wheel-colour'}
					<div class="cols">
						<label>Finish<input bind:value={rule.finish} list="powder-colour-names" maxlength="100" required /></label>
						<label>Changing from (optional)<input bind:value={rule.fromFinish} list="powder-colour-names" maxlength="100" /></label>
					</div>
				{/if}
				<label class="check"><input type="checkbox" checked={rule.quoteOnly} onchange={(event) => setQuote(rule.id, event.currentTarget.checked)} /> Shop quote only</label>
				{#if !rule.quoteOnly}
					<label>Price (₱)
						<input type="number" min="0" max="21474836" step=".01" required
							value={rule.priceCentavos === undefined ? '' : rule.priceCentavos / 100}
							oninput={(event) => setPrice(rule.id, event.currentTarget.value)} />
					</label>
				{/if}
				<label>Note (optional)<input bind:value={rule.note} maxlength="200" /></label>
				<label class="check"><input type="checkbox" bind:checked={rule.enabled} /> Use for new bookings</label>
				<div><button type="button" class="btn sm ghost" onclick={() => remove(rule.id)}><ActionIcon name="close" />Remove exception</button></div>
			</div>
		</details>
	{:else}
		<p>No exceptions yet.</p>
	{/each}
	<div><button type="button" class="btn sm" onclick={add}><ActionIcon name="add" />Add exception</button></div>
</fieldset>

<style>
	.entry { border: 1px solid var(--line); border-radius: .4rem; padding: .25rem .75rem; }
	summary { display: flex; flex-wrap: wrap; align-items: center; gap: .5rem; min-block-size: 2.75rem; cursor: pointer; }
	.body { padding-block: .5rem; }
	.chip { padding: .1rem .55rem; border: 1px solid var(--line); border-radius: 999px; font-size: .8rem; }
	.check { display: flex; align-items: center; gap: .5rem; }
	.check input { inline-size: auto; }
</style>
