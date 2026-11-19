<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';

	type Reward = { id: string; label: string; cost: number };
	type Receipt = { id: string; reward_label: string; cost: number; created_at: string; approved_at: string | null; claimed_at: string | null };
	type Points = { balance: number; rewards: Reward[]; receipts: Receipt[] };

	const time = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' });
	const attemptIds = new Map<string, string>();
	let points = $state<Points>();
	let loading = $state(true);
	let signedOut = $state(false);
	let selected = $state<Reward>();
	let busy = $state(false);
	let failure = $state('');
	let notice = $state('');

	async function load() {
		loading = true;
		failure = '';
		try {
			const response = await fetch(resolve('/api/points'));
			signedOut = response.status === 401;
			if (signedOut) {
				points = undefined;
				return;
			}
			if (!response.ok) throw new Error();
			points = await response.json();
		} catch {
			points = undefined;
			failure = 'HERCO Points are temporarily unavailable. Please try again.';
		} finally {
			loading = false;
		}
	}

	async function redeem() {
		if (!selected || busy) return;
		const reward = selected;
		busy = true;
		failure = notice = '';
		try {
			const requestId = attemptIds.get(reward.id) ?? crypto.randomUUID();
			attemptIds.set(reward.id, requestId);
			const response = await fetch(resolve('/api/points'), {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ rewardId: reward.id, requestId })
			});
			if (response.status === 401) {
				selected = undefined;
				await load();
				return;
			}
			if (!response.ok) {
				const detail = await response.json().catch(() => null);
				failure = detail?.message ?? 'Could not confirm your redemption. Please try again.';
				return;
			}
			attemptIds.delete(reward.id);
			selected = undefined;
			notice = 'Reward requested. The shop will review your redemption.';
			await load();
		} catch {
			failure = 'Could not confirm your redemption. Try again with the same reward.';
		} finally {
			busy = false;
		}
	}

	onMount(() => { void load(); });
</script>

<svelte:head><title>HERCO Points | HERCO</title></svelte:head>
<section class="section wrap stack">
	<h1>HERCO Points</h1>
	{#if failure}<p role="alert">{failure}</p>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
	{#if loading}
		<p role="status">Loading points…</p>
	{:else if signedOut}
		<p>Sign in to see your points and rewards.</p>
		<div><a class="btn sm" href={resolve('/account')}>Sign in</a></div>
	{:else if points}
		<div class="card stack">
			<h2>Points balance</h2>
			<p><strong>{points.balance.toLocaleString('en-PH')} points</strong></p>
		</div>
		<section class="card stack">
			<h2>Rewards</h2>
			{#each points.rewards as reward (reward.id)}
				<div class="row between">
					<p><strong>{reward.label}</strong> · {reward.cost.toLocaleString('en-PH')} points</p>
					<button class="btn sm ghost" disabled={busy || points.balance < reward.cost}
						onclick={() => { selected = reward; failure = notice = ''; }}>Redeem</button>
				</div>
			{:else}
				<p>The shop has no rewards available yet.</p>
			{/each}
			{#if selected}
				<div class="stack">
					<p>Use {selected.cost.toLocaleString('en-PH')} points for <strong>{selected.label}</strong>?</p>
					<div class="row">
						<button class="btn sm" disabled={busy} onclick={redeem}>Confirm redemption</button>
						<button class="btn sm ghost" disabled={busy} onclick={() => { selected = undefined; }}>Cancel</button>
					</div>
				</div>
			{/if}
		</section>
		<section class="card stack">
			<h2>Recent redemptions</h2>
			{#each points.receipts as receipt (receipt.id)}
				<div class="stack">
					<p><strong>{receipt.reward_label}</strong> · {receipt.cost.toLocaleString('en-PH')} points</p>
					<p class="small muted">Requested {time.format(new Date(receipt.created_at))} Philippine time</p>
					<p>{receipt.claimed_at ? 'Claimed ' + time.format(new Date(receipt.claimed_at)) + ' Philippine time' :
						receipt.approved_at ? 'Approved for claim' : 'Awaiting shop approval'}</p>
					<p class="small receipt-reference">{receipt.id}</p>
				</div>
			{:else}
				<p>You haven’t redeemed a reward yet.</p>
			{/each}
		</section>
	{:else}
		<div><button class="btn sm ghost" onclick={load}>Try again</button></div>
	{/if}
</section>

<style>
	.receipt-reference { overflow-wrap: anywhere; }
</style>
