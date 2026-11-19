<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { addDays, today } from '#lib/dates.ts';

	type Stock = { id: string; name: string; unit: string; category: string; minimum: number; quantity: number; revision: number;
		supplier: string | null; storage_location: string | null; unit_cost: number | null; billing_rate: number | null; capacity: number | null };
	type Activity = { request_id: string; operation: string; recorded_at: string; actor_id: string;
		input: { reason?: string }; before_value: Stock | null; after_value: Stock };
	type Inventory = { canManage: boolean; items: Stock[]; recent: Activity[] };
	const worker = import.meta.env.MODE === 'worker';
	const time = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' });
	let inventory = $state<Inventory>();
	let loading = $state(worker);
	let busy = $state(false);
	let message = $state('');
	let notice = $state('');
	let editing = $state<Stock>();
	let editingForm = $state(false);
	let name = $state('');
	let unit = $state('');
	let category = $state('');
	let supplier = $state('');
	let location = $state('');
	let unitCost = $state<number>();
	let billingRate = $state<number>();
	let capacity = $state<number>();
	const currency = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
	let minimum = $state<number>();
	let quantity = $state<number>();
	let moving = $state<Stock>();
	let delta = $state<number>();
	let reason = $state('');
	const attempts = new Map<string, string>();
	let exportFrom = $state(addDays(today(), -29));
	let exportThrough = $state(today());
	let exporting = $state(false);
	let newId: string | undefined;

	async function load() {
		loading = true;
		message = '';
		try {
			const response = await fetch(resolve('/api/inventory'));
			if (response.status === 403) throw new Error('Inventory requires staff permission and MFA.');
			if (!response.ok) throw new Error('Inventory is temporarily unavailable.');
			inventory = await response.json();
		} catch (error) {
			inventory = undefined;
			message = error instanceof Error ? error.message : 'Inventory is temporarily unavailable.';
		} finally {
			loading = false;
		}
	}

	function edit(item?: Stock) {
		editing = item;
		editingForm = true;
		moving = undefined;
		newId = undefined;
		name = item?.name ?? '';
		unit = item?.unit ?? '';
		category = item?.category ?? '';
		supplier = item?.supplier ?? '';
		location = item?.storage_location ?? '';
		unitCost = item?.unit_cost ?? undefined;
		billingRate = item?.billing_rate ?? undefined;
		capacity = item?.capacity ?? undefined;
		minimum = item?.minimum;
		quantity = undefined;
		message = notice = '';
	}

	function move(item: Stock) {
		moving = item;
		editingForm = false;
		delta = undefined;
		reason = '';
		message = notice = '';
	}

	async function write(operation: string, stockId: string, details: Record<string, unknown>) {
		if (busy) return;
		busy = true;
		message = notice = '';
		const fingerprint = JSON.stringify({ operation, stockId, details });
		const requestId = attempts.get(fingerprint) ?? crypto.randomUUID();
		attempts.set(fingerprint, requestId);
		try {
			const response = await fetch(resolve('/api/inventory'), {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ operation, stockId, details, requestId })
			});
			if (!response.ok) {
				const detail = await response.json().catch(() => null);
				throw new Error(detail?.message ?? 'Could not confirm the inventory update.');
			}
			attempts.delete(fingerprint);
			editingForm = false;
			moving = undefined;
			notice = 'Inventory updated.';
			await load();
		} catch (error) {
			message = error instanceof Error ? error.message : 'Could not confirm the inventory update.';
		} finally {
			busy = false;
		}
	}

	function submitItem(event: SubmitEvent) {
		event.preventDefault();
		const fields = { name: name.trim(), unit: unit.trim(), category: category.trim(), minimum,
			supplier: supplier.trim(), storage_location: location.trim(),
			unit_cost: unitCost ?? null, billing_rate: billingRate ?? null, capacity: capacity ?? null };
		if (editing) void write('edit', editing.id, { ...fields, revision: editing.revision });
		else {
			newId ??= crypto.randomUUID();
			void write('create', newId, { ...fields, quantity });
		}
	}

	function submitMovement(event: SubmitEvent) {
		event.preventDefault();
		if (moving) void write('move', moving.id, { delta, reason: reason.trim() });
	}

	async function exportCsv(kind: 'stock' | 'movements') {
		if (exporting) return;
		exporting = true;
		message = '';
		try {
			const query = new URLSearchParams({ kind });
			if (kind === 'movements') {
				query.set('from', exportFrom);
				query.set('through', exportThrough);
			}
			const response = await fetch(resolve('/api/inventory/export') + '?' + query, { headers: { accept: 'text/csv' } });
			if (!response.ok) {
				const detail = await response.json().catch(() => null);
				throw Error(detail?.message ?? 'Could not export inventory. Please try again.');
			}
			const url = URL.createObjectURL(await response.blob());
			const link = document.createElement('a');
			link.href = url;
			link.download = 'herco-inventory-' + kind + '.csv';
			link.click();
			window.setTimeout(() => URL.revokeObjectURL(url), 1000);
		} catch (error) {
			message = error instanceof Error ? error.message : 'Could not export inventory. Please try again.';
		} finally { exporting = false; }
	}

	onMount(() => { if (worker) void load(); });
</script>

<svelte:head><title>Inventory | HERCO</title></svelte:head>
<section class="section wrap stack">
	<h1>Inventory</h1>
	{#if message}<p role="alert">{message}</p>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
	{#if loading}
		<p role="status">Loading inventory…</p>
	{:else if inventory}
		<details class="card">
			<summary>Download inventory CSV</summary>
			<div class="stack">
				<div><button class="btn sm ghost" disabled={exporting} onclick={() => exportCsv('stock')}>Stock on hand</button></div>
				<div class="row">
					<label>Movement history from<input type="date" bind:value={exportFrom} required /></label>
					<label>Through<input type="date" bind:value={exportThrough} min={exportFrom || undefined} required /></label>
					<button class="btn sm ghost" disabled={exporting || !exportFrom || !exportThrough || exportFrom > exportThrough}
						onclick={() => exportCsv('movements')}>Stock movements</button>
				</div>
			</div>
		</details>
		{#if inventory.canManage}
			<div><button class="btn sm" onclick={() => edit()} disabled={busy}>Add item</button></div>
		{/if}
		{#if editingForm}
			<form class="card stack" onsubmit={submitItem}>
				<h2>{editing ? 'Edit item' : 'Add item'}</h2>
				<label>Item name<input bind:value={name} maxlength="120" required /></label>
				<label>Unit<input bind:value={unit} maxlength="30" required /></label>
				<label>Category<input bind:value={category} maxlength="60" /></label>
				<label>Supplier (optional)<input bind:value={supplier} maxlength="120" /></label>
				<label>Storage location (optional)<input bind:value={location} maxlength="120" /></label>
				<label>Unit cost (₱, optional)<input type="number" bind:value={unitCost} min="0" step=".01" /></label>
				<label>Billing rate (₱, optional)<input type="number" bind:value={billingRate} min="0" step=".01" /></label>
				<label>Storage capacity (optional)<input type="number" bind:value={capacity} min="0" step=".001" /></label>
				<label>Low-stock threshold<input type="number" bind:value={minimum} min="0" step=".001" required /></label>
				{#if !editing}<label>Opening stock<input type="number" bind:value={quantity} min="0" step=".001" required /></label>{/if}
				<div class="row"><button class="btn sm" disabled={busy}>Save item</button>
					<button class="btn sm ghost" type="button" disabled={busy} onclick={() => { editingForm = false; }}>Cancel</button></div>
			</form>
		{/if}
		{#if moving}
			<form class="card stack" onsubmit={submitMovement}>
				<h2>Adjust {moving.name}</h2>
				<label>Quantity to add or subtract<input bind:value={delta} type="number" step=".001" required /></label>
				<label>Reason<input bind:value={reason} maxlength="300" required /></label>
				<div class="row"><button class="btn sm" disabled={busy}>Save adjustment</button>
					<button class="btn sm ghost" type="button" disabled={busy} onclick={() => { moving = undefined; }}>Cancel</button></div>
			</form>
		{/if}
		{#each inventory.items as item (item.id)}
			<article class="card stack">
				<h2>{item.name}</h2>
				<p><strong>{item.quantity} {item.unit}</strong>{item.category ? ' · ' + item.category : ''}</p>
				{#if item.quantity <= item.minimum}<p>Low stock · threshold {item.minimum} {item.unit}</p>{/if}
				{#if item.supplier}<p>Supplier · {item.supplier}</p>{/if}
				{#if item.storage_location}<p>Storage location · {item.storage_location}</p>{/if}
				{#if item.unit_cost != null}<p>Unit cost · {currency.format(item.unit_cost)}</p>{/if}
				{#if item.billing_rate != null}<p>Billing rate · {currency.format(item.billing_rate)}</p>{/if}
				{#if item.capacity != null}<p>Storage capacity · {item.capacity} {item.unit}</p>{/if}
				{#if inventory.canManage}
					<div class="row"><button class="btn sm ghost" disabled={busy} onclick={() => edit(item)}>Edit</button>
						<button class="btn sm ghost" disabled={busy} onclick={() => move(item)}>Adjust stock</button></div>
				{/if}
			</article>
		{:else}
			<p>No inventory items yet.</p>
		{/each}
		<details class="card">
			<summary>Recent stock activity</summary>
			<ul>
				{#each inventory.recent as entry (entry.actor_id + entry.request_id)}
					<li>{entry.after_value.name} · {entry.operation === 'move' ? 'Stock adjusted' : entry.operation === 'create' ? 'Item added' : 'Item edited'} ·
						{time.format(new Date(entry.recorded_at))} Philippine time
						{#if entry.input.reason}<p>{entry.input.reason} · {entry.before_value?.quantity} → {entry.after_value.quantity} {entry.after_value.unit}</p>{/if}
					</li>
				{:else}
					<li>No stock activity yet.</li>
				{/each}
			</ul>
		</details>
	{:else if worker}
		<div class="row"><a class="btn sm ghost" href={resolve('/admin')}>Staff workspace</a>
			<button class="btn sm ghost" onclick={load}>Try again</button></div>
	{:else}
		<p>The inventory workspace is available in the server build.</p>
	{/if}
</section>
