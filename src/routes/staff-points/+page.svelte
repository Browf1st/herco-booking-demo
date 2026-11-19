<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';

	type Receipt = { id: string; member_id: string; reward_label: string; cost: number; created_at: string;
		approved_at: string | null; approved_by: string | null; claimed_at: string | null; claimed_by: string | null };
	type Reward = { id: string; label: string; cost: number; enabled: boolean };
	const stamp = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' });
	let data = $state<{ actions: string[]; receipts: Receipt[]; rewards: Reward[] }>();
	let loading = $state(import.meta.env.MODE === 'worker');
	let busy = $state(false);
	let failure = $state('');
	let notice = $state('');
	let member = $state('');
	let delta = $state<number>();
	let reason = $state('');
	let adjustment: { fingerprint: string; id: string } | undefined;
	let draft = $state<{ id?: string; label: string; cost?: number; enabled: boolean }>({ label: '', enabled: false });

	async function load() {
		loading = true;
		try {
			const response = await fetch(resolve('/api/staff-points'));
			if (response.status === 403) throw new Error('Staff permission and MFA are required.');
			if (!response.ok) throw new Error('The points workspace is temporarily unavailable.');
			data = await response.json();
		} catch (error) {
			data = undefined;
			failure = error instanceof Error ? error.message : 'Could not reach HERCO Points.';
		} finally {
			loading = false;
		}
	}

	async function submit(payload: Record<string, unknown>) {
		if (busy) return false;
		busy = true;
		failure = notice = '';
		try {
			const response = await fetch(resolve('/api/staff-points'), {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify(payload)
			});
			if (!response.ok) {
				const detail = await response.json().catch(() => null);
				throw new Error(detail?.message ?? 'Could not confirm this update.');
			}
			notice = 'Update saved.';
			await load();
			return true;
		} catch (error) {
			failure = error instanceof Error ? error.message : 'Could not reach HERCO Points.';
			return false;
		} finally {
			busy = false;
		}
	}

	async function adjust(event: SubmitEvent) {
		event.preventDefault();
		const payload = { member: member.trim(), delta, reason: reason.trim() };
		const fingerprint = JSON.stringify(payload);
		if (adjustment?.fingerprint !== fingerprint) adjustment = { fingerprint, id: crypto.randomUUID() };
		if (await submit({ action: 'adjust', ...payload, requestId: adjustment.id })) {
			adjustment = undefined;
			member = reason = '';
			delta = undefined;
		}
	}

	async function saveReward(event: SubmitEvent) {
		event.preventDefault();
		draft.id ??= crypto.randomUUID();
		if (await submit({ action: 'saveReward', ...draft })) draft = { label: '', enabled: false };
	}

	onMount(() => { if (import.meta.env.MODE === 'worker') void load(); });
</script>

<svelte:head><title>Manage HERCO Points | HERCO</title></svelte:head>
<section class="section wrap stack">
	<h1>Manage HERCO Points</h1>
	{#if failure}<p role="alert">{failure}</p>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
	{#if loading}
		<p role="status">Loading points workspace…</p>
	{:else if data}
		{#if data.actions.includes('managePoints')}
			<form class="card stack" onsubmit={adjust}>
				<h2>Adjust points</h2>
				<label>Member ID<input bind:value={member} required maxlength="36" /></label>
				<label>Points to add or subtract<input type="number" bind:value={delta} required step="1" /></label>
				<label>Reason<input bind:value={reason} required maxlength="300" /></label>
				<div><button class="btn sm" disabled={busy}>Save adjustment</button></div>
			</form>
		{/if}
		{#if data.actions.includes('manageRewards')}
			<form class="card stack" onsubmit={saveReward}>
				<h2>{draft.id ? 'Edit reward' : 'Add reward'}</h2>
				<label>Reward name<input bind:value={draft.label} required maxlength="120" /></label>
				<label>Point cost<input type="number" bind:value={draft.cost} min="1" required /></label>
				<label><input type="checkbox" bind:checked={draft.enabled} /> Available to customers</label>
				<div class="row">
					<button class="btn sm" disabled={busy}>Save reward</button>
					{#if draft.id}<button type="button" class="btn sm ghost" disabled={busy}
						onclick={() => { draft = { label: '', enabled: false }; }}>Clear</button>{/if}
				</div>
				{#each data.rewards as reward (reward.id)}
					<div class="row between">
						<p>{reward.label} · {reward.cost} points · {reward.enabled ? 'Available' : 'Disabled'}</p>
						<button class="btn sm ghost" type="button" disabled={busy} onclick={() => { draft = { ...reward }; }}>Edit</button>
					</div>
				{/each}
			</form>
		{/if}
		<section class="card stack">
			<h2>Recent redemptions</h2>
			{#each data.receipts as receipt (receipt.id)}
				<article class="stack">
					<p><strong>{receipt.reward_label}</strong> · {receipt.cost} points</p>
					<p class="small identity">Receipt {receipt.id} · Member {receipt.member_id}</p>
					<p>Requested {stamp.format(new Date(receipt.created_at))} Philippine time</p>
					{#if receipt.approved_at}<p class="small identity">Approved by {receipt.approved_by} · {stamp.format(new Date(receipt.approved_at))}</p>{/if}
					{#if receipt.claimed_at}
						<p class="small identity">Claimed by {receipt.claimed_by} · {stamp.format(new Date(receipt.claimed_at))}</p>
					{:else if !receipt.approved_at && data.actions.includes('approveRewards')}
						<div><button class="btn sm ghost" disabled={busy} onclick={() => submit({ action: 'approve', receipt: receipt.id })}>Approve</button></div>
					{:else if receipt.approved_at && data.actions.includes('claimRewards')}
						<div><button class="btn sm ghost" disabled={busy} onclick={() => submit({ action: 'claim', receipt: receipt.id })}>Mark claimed</button></div>
					{/if}
				</article>
			{:else}
				<p>No redemptions yet.</p>
			{/each}
		</section>
	{:else if import.meta.env.MODE === 'worker'}
		<div class="row"><a class="btn sm ghost" href={resolve('/admin')}>Staff workspace</a>
			<button class="btn sm ghost" onclick={() => { failure = ''; void load(); }}>Try again</button></div>
	{:else}
		<p>The points workspace is available in the server build.</p>
	{/if}
</section>

<style>
	.identity { overflow-wrap: anywhere; }
</style>
