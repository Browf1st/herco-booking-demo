<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// "Edit service" popup: the booking's current services are ticked, staff untick to remove or tick catalog options to add,
	// then see a summary (added, removed, new total) before pressing Confirm. The screen behind does the saving (onapply).
	import { tick } from 'svelte';
	import ActionIcon from './ActionIcon.svelte';
	import { formatCentavos } from './booking-changes';
	import { summarizeServiceChange, type ChangeLine } from './service-change';
	import type { AddOption, EditableLine, SaveResult } from './ServiceLinesEditor.svelte';

	let { lines, addOptions, canAdd, canRemove, onapply }: {
		lines: EditableLine[]; addOptions: AddOption[]; canAdd: boolean; canRemove: boolean;
		onapply: (wanted: string[]) => Promise<SaveResult>;
	} = $props();
	const id = $props.id();
	let dialog = $state<HTMLDialogElement>();
	let wanted = $state<string[]>([]);
	let issue = $state('');
	let busy = $state(false);

	const asLine = (line: { code: string; label: string; centavos?: number; price?: string }): ChangeLine => ({ code: line.code, label: line.label, centavos: line.centavos });
	const current = $derived(lines.map(asLine));
	const options = $derived(addOptions.map(asLine));
	const summary = $derived(summarizeServiceChange(current, options, wanted));
	const money = (line: ChangeLine) => typeof line.centavos === 'number' ? formatCentavos(line.centavos) : 'price on quote';

	export async function open() {
		wanted = lines.map((line) => line.code);
		issue = '';
		dialog?.showModal();
		await tick();
	}
	function toggle(code: string, checked: boolean) { wanted = checked ? [...wanted, code] : wanted.filter((item) => item !== code); issue = ''; }
	async function confirm() {
		if (busy || summary.problem) return;
		busy = true; issue = '';
		const result = await onapply(wanted);
		busy = false;
		if (result.ok) dialog?.close(); else issue = result.message;
	}
</script>

<!-- Esc is blocked while saving, like the disabled Close and Cancel buttons, so the failure message is not lost. -->
<dialog bind:this={dialog} aria-labelledby={id + '-title'} oncancel={(event) => { if (busy) event.preventDefault(); }}>
	<header><h3 id={id + '-title'}>Edit services</h3><button type="button" class="close" disabled={busy} onclick={() => dialog?.close()}>Close</button></header>
	<div class="body">
		<fieldset>
			<legend>Current services <span class="muted small">(untick to remove)</span></legend>
			{#each lines as line (line.code)}
				<label class="row-check"><input type="checkbox" checked={wanted.includes(line.code)} disabled={busy || !canRemove} onchange={(event) => toggle(line.code, event.currentTarget.checked)} /><span>{line.label}</span>{#if line.price}<b>{line.price}</b>{/if}</label>
			{/each}
		</fieldset>
		{#if canAdd}
			<fieldset>
				<legend>Add from the catalog</legend>
				{#each addOptions as option (option.code)}
					<label class="row-check"><input type="checkbox" checked={wanted.includes(option.code)} disabled={busy} onchange={(event) => toggle(option.code, event.currentTarget.checked)} /><span>{option.label}</span>{#if option.price}<b>{option.price}</b>{/if}</label>
				{:else}<p class="muted small">No other services are available for this visit.</p>{/each}
			</fieldset>
		{/if}
		<section class="summary" aria-live="polite" aria-label="Summary of the change">
			<h4>Summary of the change</h4>
			{#if summary.problem}<p class="muted small">{summary.problem}</p>{/if}
			{#each summary.added as line (line.code)}<p class="add"><ActionIcon name="add" /><span>Added {line.label}</span><b>{money(line)}</b></p>{/each}
			{#each summary.removed as line (line.code)}<p class="remove"><ActionIcon name="close" /><span>Removed {line.label}</span><b>{money(line)}</b></p>{/each}
			<p class="total"><span>New total</span><b>{typeof summary.totalCentavos === 'number' ? formatCentavos(summary.totalCentavos) : 'The shop will confirm the total'}</b></p>
		</section>
		{#if issue}<p class="error small" role="alert">{issue}</p>{/if}
		<div class="row"><button type="button" class="btn sm" disabled={busy || Boolean(summary.problem)} onclick={confirm}>{busy ? 'Saving…' : 'Confirm changes'}</button><button type="button" class="btn sm ghost" disabled={busy} onclick={() => dialog?.close()}>Cancel</button></div>
	</div>
</dialog>

<style>
	dialog { box-sizing: border-box; display: none; width: min(32rem, calc(100% - 1.5rem)); max-height: 90dvh; margin: auto; padding: 0; border: 1px solid var(--line); border-radius: 14px; background: var(--panel); color: var(--text); overflow: hidden; }
	dialog[open] { display: flex; flex-direction: column; }
	dialog::backdrop { background: #0009; }
	header { display: flex; align-items: center; justify-content: space-between; gap: .75rem; padding: .8rem 1rem; border-bottom: 1px solid var(--line); }
	h3 { margin: 0; font-size: 1.2rem; }
	.close { min-height: 2.75rem; padding: 0 .9rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); color: var(--text); font: 700 .85rem var(--body); cursor: pointer; }
	.body { display: grid; gap: .8rem; padding: 1rem; overflow-y: auto; overflow-wrap: anywhere; }
	fieldset { display: grid; gap: .3rem; margin: 0; padding: .7rem; border: 1px solid var(--line); border-radius: 10px; }
	legend { padding-inline: .3rem; font-size: .75rem; font-weight: 800; letter-spacing: .05em; text-transform: uppercase; }
	.row-check { display: grid; grid-template-columns: auto minmax(0, 1fr) auto; align-items: center; gap: .6rem; min-height: 2.75rem; }
	.row-check input { width: 1.25rem; height: 1.25rem; }
	.summary { display: grid; gap: .35rem; padding: .7rem; border: 1px solid var(--line); border-radius: 10px; background: var(--panel-2); }
	h4 { margin: 0; font-size: .75rem; letter-spacing: .05em; text-transform: uppercase; }
	.summary p { display: flex; align-items: center; gap: .5rem; margin: 0; }
	.summary p span { flex: 1; }
	.add { color: var(--ok); }
	.remove { color: var(--bad); }
	.total { padding-top: .4rem; border-top: 1px solid var(--line); font-weight: 800; }
	p { margin: 0; }
</style>
