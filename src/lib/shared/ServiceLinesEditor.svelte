<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script module lang="ts">
	export type EditableLine = { code: string; label: string; price?: string; currentPesos?: number; canEditPrice: boolean; parts?: { label: string; price?: string }[] };
	export type AddOption = { code: string; label: string; price?: string };
	export type SaveResult = { ok: true } | { ok: false; message: string; reload?: boolean };
</script>

<script lang="ts">
	// The service lines of one booking, with "Edit price", "Remove" and "Add service" for staff who may use them.
	// It only draws the screen and checks what was typed. The live and demo screens do the saving (onsaveprice, onadd, onremove).
	import { tick } from 'svelte';
	import { parsePesos, parseReason } from './booking-changes';

	let { lines, canAdd = false, canRemove = false, addOptions = [], onsaveprice, onadd, onremove, onreload }: {
		lines: EditableLine[]; canAdd?: boolean; canRemove?: boolean; addOptions?: AddOption[];
		onsaveprice: (code: string, pesos: number, reason: string) => Promise<SaveResult>;
		onadd?: (code: string) => Promise<SaveResult>; onremove?: (code: string) => Promise<SaveResult>; onreload?: () => Promise<void>;
	} = $props();
	const id = $props.id();
	let editing = $state<string>();
	let priceText = $state('');
	let reasonText = $state('');
	let fieldError = $state('');
	let priceInput = $state<HTMLInputElement>();
	let adding = $state(false);
	let pick = $state('');
	let addError = $state('');
	let issue = $state('');
	let canReload = $state(false);
	let notice = $state('');
	let busy = $state(false);

	function clearMessages() { fieldError = addError = issue = notice = ''; canReload = false; }
	async function startEdit(line: EditableLine) {
		clearMessages(); adding = false;
		editing = line.code; priceText = reasonText = '';
		await tick();
		priceInput?.focus();
	}
	function failed(result: Extract<SaveResult, { ok: false }>, where: 'field' | 'add' | 'line') {
		if (where === 'field') fieldError = result.message; else if (where === 'add') addError = result.message; else issue = result.message;
		canReload = Boolean(result.reload && onreload);
	}
	async function savePrice(event: SubmitEvent, line: EditableLine) {
		event.preventDefault();
		if (busy) return;
		clearMessages();
		const price = parsePesos(priceText);
		if (!price.ok) { fieldError = price.message; return; }
		if (price.pesos === line.currentPesos) { fieldError = 'That is already the price.'; return; }
		const reason = parseReason(reasonText);
		if (!reason.ok) { fieldError = reason.message; return; }
		busy = true;
		const result = await onsaveprice(line.code, price.pesos, reason.reason);
		busy = false;
		if (result.ok) { editing = undefined; notice = 'Price saved for ' + line.label + '.'; } else failed(result, 'field');
	}
	// "Remove" first asks "Remove X? Yes / No" on the line; only Yes removes it.
	let confirming = $state<string>();
	function askRemove(line: EditableLine) { clearMessages(); editing = undefined; confirming = line.code; }
	async function remove(line: EditableLine) {
		if (busy || !onremove) return;
		confirming = undefined;
		clearMessages(); editing = undefined; busy = true;
		const result = await onremove(line.code);
		busy = false;
		if (result.ok) notice = 'Removed ' + line.label + '.'; else failed(result, 'line');
	}
	async function add(event: SubmitEvent) {
		event.preventDefault();
		if (busy || !onadd) return;
		clearMessages();
		if (!pick) { addError = 'Choose a service to add.'; return; }
		const label = addOptions.find((option) => option.code === pick)?.label ?? 'service';
		busy = true;
		const result = await onadd(pick);
		busy = false;
		if (result.ok) { adding = false; pick = ''; notice = 'Added ' + label + '.'; } else failed(result, 'add');
	}
	async function reload() {
		busy = true;
		await onreload?.();
		busy = false;
		clearMessages(); editing = undefined;
	}
	function openAdd() { clearMessages(); editing = undefined; pick = ''; adding = true; }
</script>

<div class="editor">
	{#if lines.length}
		<ul>{#each lines as line (line.code)}
			<li>
				<span class="line"><span>{line.label}</span>{#if line.price}<b>{line.price}</b>{/if}</span>
				{#if line.parts?.length}<ul class="parts">{#each line.parts as part}<li class="line"><span>{part.label}</span>{#if part.price}<span>{part.price}</span>{/if}</li>{/each}</ul>{/if}
				{#if confirming === line.code}
						<span class="tools confirm" role="group" aria-label={'Remove ' + line.label + '?'}>
							<span class="small">Remove {line.label}?</span>
							<button type="button" class="btn sm ghost danger" disabled={busy} onclick={() => remove(line)}>Yes</button>
							<button type="button" class="btn sm ghost" disabled={busy} onclick={() => confirming = undefined}>No</button>
						</span>
					{:else if editing !== line.code && (line.canEditPrice || (canRemove && lines.length > 1))}
					<span class="tools">
						{#if line.canEditPrice}<button type="button" class="btn sm ghost" disabled={busy} aria-label={'Edit price for ' + line.label} onclick={() => startEdit(line)}>Edit price</button>{/if}
						{#if canRemove && lines.length > 1}<button type="button" class="btn sm ghost danger" disabled={busy} aria-label={'Remove ' + line.label} onclick={() => askRemove(line)}>Remove</button>{/if}
					</span>
				{/if}
				{#if editing === line.code}
					<form class="inline" onsubmit={(event) => savePrice(event, line)} aria-label={'Edit price for ' + line.label}>
						<label>New price (₱)
							<input bind:this={priceInput} bind:value={priceText} type="text" inputmode="numeric" autocomplete="off" disabled={busy} aria-invalid={fieldError ? 'true' : undefined} aria-describedby={fieldError ? id + '-error' : undefined} />
						</label>
						<label>Reason
							<input bind:value={reasonText} type="text" maxlength="200" autocomplete="off" placeholder="For example: Extra corrosion found" disabled={busy} aria-invalid={fieldError ? 'true' : undefined} aria-describedby={fieldError ? id + '-error' : undefined} />
						</label>
						{#if fieldError}<p class="error small" id={id + '-error'} role="alert">{fieldError}</p>{/if}
						{#if canReload}<div><button type="button" class="btn sm ghost" disabled={busy} onclick={reload}>Reload</button></div>{/if}
						<div class="row"><button class="btn sm" disabled={busy}>{busy ? 'Saving…' : 'Save'}</button><button type="button" class="btn sm ghost" disabled={busy} onclick={() => { editing = undefined; clearMessages(); }}>Cancel</button></div>
					</form>
				{/if}
			</li>
		{/each}</ul>
	{:else}<p class="muted small">No services listed.</p>{/if}

	{#if canAdd}
		{#if adding}
			<form class="inline" onsubmit={add} aria-label="Add service">
				{#if addOptions.length}
					<label>Service to add
						<select bind:value={pick} disabled={busy} aria-invalid={addError ? 'true' : undefined} aria-describedby={addError ? id + '-add-error' : undefined}>
							<option value="">Choose a service</option>
							{#each addOptions as option (option.code)}<option value={option.code}>{option.label}{option.price ? ' · ' + option.price : ''}</option>{/each}
						</select>
					</label>
				{:else}<p class="muted small">No other services are available for this visit.</p>{/if}
				{#if addError}<p class="error small" id={id + '-add-error'} role="alert">{addError}</p>{/if}
				{#if canReload && !editing}<div><button type="button" class="btn sm ghost" disabled={busy} onclick={reload}>Reload</button></div>{/if}
				<div class="row">{#if addOptions.length}<button class="btn sm" disabled={busy}>{busy ? 'Adding…' : 'Add'}</button>{/if}<button type="button" class="btn sm ghost" disabled={busy} onclick={() => { adding = false; clearMessages(); }}>Cancel</button></div>
			</form>
		{:else}
			<div><button type="button" class="btn sm ghost" disabled={busy} onclick={openAdd}>Add service</button></div>
		{/if}
	{/if}

	{#if issue}
		<p class="error small" role="alert">{issue}</p>
		{#if canReload && !adding}<div><button type="button" class="btn sm ghost" disabled={busy} onclick={reload}>Reload</button></div>{/if}
	{/if}
	{#if notice}<p class="small ok" role="status">{notice}</p>{/if}
</div>

<style>
	.editor { display: grid; gap: .5rem; }
	ul { display: grid; gap: .6rem; margin: 0; padding: 0; list-style: none; }
	li { display: grid; gap: .4rem; }
	.line { display: flex; justify-content: space-between; gap: .75rem; }
	li > .line { font-weight: 700; }
	.parts { margin: .1rem 0 0 .6rem; padding-left: .8rem; border-left: 2px solid var(--line); color: var(--muted); font-size: .85rem; }
	.tools { display: flex; flex-wrap: wrap; align-items: center; gap: .4rem; }
	.confirm button { min-width: 2.75rem; }
	.inline { display: grid; gap: .5rem; padding: .7rem; border: 1px solid var(--line); border-radius: 10px; background: var(--panel-2); }
	.inline label { display: grid; gap: .25rem; font-size: .85rem; font-weight: 700; }
	.danger { color: var(--bad); border-color: var(--bad-line); }
	.ok { color: var(--ok); }
	p { margin: 0; }
	button { min-height: 2.75rem; }
</style>
