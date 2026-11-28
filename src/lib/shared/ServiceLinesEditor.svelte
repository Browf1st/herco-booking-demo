<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script module lang="ts">
	export type EditablePart = { label: string; price?: string; /** The part's current price in whole pesos, when it is a whole peso (for prefilling the edit box). */ currentPesos?: number };
	export type EditableLine = { code: string; label: string; price?: string; /** The line's price in centavos (for the change summary). */ centavos?: number; currentPesos?: number; canEditPrice: boolean; parts?: EditablePart[] };
	export type AddOption = { code: string; label: string; price?: string; centavos?: number };
	export type SaveResult = { ok: true } | { ok: false; message: string; reload?: boolean };
</script>

<script lang="ts">
	// The service lines of one booking, with "Edit price" (current price beside the proposed one) and "Edit services" (a popup with a summary) for staff who may use them.
	// It only draws the screen and checks what was typed. The live screen does the saving (onsaveprice, onapply).
	import { tick } from 'svelte';
	import { parsePesos, parseReason } from './booking-changes';
	import ServiceChangeDialog from './ServiceChangeDialog.svelte';

	let { lines, canAdd = false, canRemove = false, addOptions = [], onsaveprice, onapply, onreload }: {
		lines: EditableLine[]; canAdd?: boolean; canRemove?: boolean; addOptions?: AddOption[];
		/** Saves the new per-part prices of one line (base plus each option, in order). A line with no options sends one part. */
		onsaveprice: (code: string, parts: { label: string; pesos: number }[], reason: string) => Promise<SaveResult>;
		/** Gets every service code wanted after the change. */
		onapply?: (wanted: string[]) => Promise<SaveResult>; onreload?: () => Promise<void>;
	} = $props();
	const id = $props.id();
	let editing = $state<string>();
	// One editable box per part of the line being edited (base plus each option).
	let editParts = $state<{ label: string; current?: number; pesos: string }[]>([]);
	let reasonText = $state('');
	let fieldError = $state('');
	let root = $state<HTMLDivElement>();
	const peso = (value: number) => '₱' + value.toLocaleString('en-PH');
	// The line's parts, or a single "base" part when it has no options.
	function partsOf(line: EditableLine) {
		return line.parts?.length ? line.parts.map((part) => ({ label: part.label, current: part.currentPesos }))
			: [{ label: line.label, current: line.currentPesos }];
	}
	// Live total of the boxes while editing; undefined until every box holds a valid whole-peso amount.
	const parsedParts = $derived(editParts.map((part) => parsePesos(part.pesos)));
	const newTotal = $derived(parsedParts.every((result) => result.ok)
		? parsedParts.reduce((sum, result) => sum + (result.ok ? result.pesos : 0), 0) : undefined);
	let serviceDialog = $state<{ open: () => Promise<void> }>();
	let issue = $state('');
	let canReload = $state(false);
	let notice = $state('');
	let busy = $state(false);

	function clearMessages() { fieldError = issue = notice = ''; canReload = false; }
	async function startEdit(line: EditableLine) {
		clearMessages();
		editing = line.code; reasonText = '';
		editParts = partsOf(line).map((part) => ({ label: part.label, current: part.current, pesos: part.current != null ? String(part.current) : '' }));
		await tick();
		root?.querySelector<HTMLInputElement>('.parts-edit input')?.focus();
	}
	function failed(result: Extract<SaveResult, { ok: false }>) {
		fieldError = result.message;
		canReload = Boolean(result.reload && onreload);
	}
	async function savePrice(event: SubmitEvent, line: EditableLine) {
		event.preventDefault();
		if (busy) return;
		clearMessages();
		const parsed = editParts.map((part) => ({ label: part.label, result: parsePesos(part.pesos) }));
		const invalid = parsed.find((part) => !part.result.ok);
		if (invalid && !invalid.result.ok) { fieldError = invalid.result.message; return; }
		const parts = parsed.map((part) => ({ label: part.label, pesos: part.result.ok ? part.result.pesos : 0 }));
		// Nothing changed: every box still holds the current price.
		if (editParts.every((part, index) => part.current != null && parts[index].pesos === part.current)) { fieldError = 'That is already the price.'; return; }
		const reason = parseReason(reasonText);
		if (!reason.ok) { fieldError = reason.message; return; }
		busy = true;
		const result = await onsaveprice(line.code, parts, reason.reason);
		busy = false;
		if (result.ok) { editing = undefined; notice = 'Price saved for ' + line.label + '.'; } else failed(result);
	}
	// Edit services: the popup shows a summary first, then calls this with every code wanted.
	async function apply(wanted: string[]) {
		clearMessages(); editing = undefined;
		const result = await onapply?.(wanted) ?? { ok: false as const, message: 'Editing services is not available.' };
		if (result.ok) notice = 'Services updated.'; else canReload = Boolean(result.reload && onreload);
		return result;
	}
	async function reload() {
		busy = true;
		await onreload?.();
		busy = false;
		clearMessages(); editing = undefined;
	}
	/** The top-right Edit price / Edit service buttons call this: scroll here, then open the right editor. */
	export async function reveal(mode: 'price' | 'service') {
		root?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
		if (mode === 'service') { await serviceDialog?.open(); return; }
		const editable = lines.filter((line) => line.canEditPrice);
		if (editable.length === 1) await startEdit(editable[0]);
		else root?.querySelector<HTMLButtonElement>('button[data-edit-price]')?.focus();
	}
	const canEditServices = $derived((canAdd || canRemove) && Boolean(onapply));
</script>

<div class="editor" bind:this={root}>
	{#if lines.length}
		<ul>{#each lines as line (line.code)}
			<li>
				<span class="line"><span>{line.label}</span>{#if line.price}<b>{line.price}</b>{/if}</span>
				{#if line.parts?.length}<ul class="parts">{#each line.parts as part}<li class="line"><span>{part.label}</span>{#if part.price}<span>{part.price}</span>{/if}</li>{/each}</ul>{/if}
				{#if line.canEditPrice && editing !== line.code}
					<span class="tools"><button type="button" class="btn sm ghost" data-edit-price disabled={busy} aria-label={'Edit price for ' + line.label} onclick={() => startEdit(line)}>Edit price</button></span>
				{/if}
				{#if editing === line.code}
					<form class="inline" onsubmit={(event) => savePrice(event, line)} aria-label={'Edit price for ' + line.label}>
						<div class="parts-edit">
							{#each editParts as part, index (index)}
								<label>{part.label}{#if part.current != null} <span class="muted">now {peso(part.current)}</span>{/if}
									<input bind:value={editParts[index].pesos} type="text" inputmode="numeric" autocomplete="off" disabled={busy} aria-invalid={fieldError ? 'true' : undefined} aria-describedby={fieldError ? id + '-error' : undefined} />
								</label>
							{/each}
						</div>
						<p class="total"><span>New total</span><b>{newTotal != null ? peso(newTotal) : '—'}</b></p>
						<label>Reason <span class="muted">(staff only, the customer does not see it)</span>
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

	{#if canEditServices}
		<div><button type="button" class="btn sm ghost" disabled={busy} onclick={() => serviceDialog?.open()}>Edit services</button></div>
		<ServiceChangeDialog bind:this={serviceDialog} {lines} {addOptions} {canAdd} {canRemove} onapply={apply} />
	{/if}

	{#if issue}
		<p class="error small" role="alert">{issue}</p>
		{#if canReload}<div><button type="button" class="btn sm ghost" disabled={busy} onclick={reload}>Reload</button></div>{/if}
	{/if}
	{#if notice}<p class="small ok" role="status">{notice}</p>{/if}
	{#if canReload && !editing && !issue}<div><button type="button" class="btn sm ghost" disabled={busy} onclick={reload}>Reload</button></div>{/if}
</div>

<style>
	.editor { display: grid; gap: .5rem; }
	ul { display: grid; gap: .6rem; margin: 0; padding: 0; list-style: none; }
	li { display: grid; gap: .4rem; }
	.line { display: flex; justify-content: space-between; gap: .75rem; }
	li > .line { font-weight: 700; }
	.parts { margin: .1rem 0 0 .6rem; padding-left: .8rem; border-left: 2px solid var(--line); color: var(--muted); font-size: .85rem; }
	.tools { display: flex; flex-wrap: wrap; align-items: center; gap: .4rem; }
	.parts-edit { display: grid; gap: .5rem; }
	.parts-edit label .muted { font-weight: 400; }
	.total { display: flex; justify-content: space-between; gap: .75rem; align-items: baseline; margin: 0; font-weight: 700; }
	.inline { display: grid; gap: .5rem; padding: .7rem; border: 1px solid var(--line); border-radius: 10px; background: var(--panel-2); }
	.inline label { display: grid; gap: .25rem; font-size: .85rem; font-weight: 700; }
	.ok { color: var(--ok); }
	p { margin: 0; }
	button { min-height: 2.75rem; }
</style>
