<script lang="ts">
	import { resolve } from '$app/paths';
	import { account } from '#lib/account.svelte.ts';
	import { ops, fanRanking, pointBalance, redeemReward } from '#lib/operations.svelte.ts';
	import RewardReceipt from '#lib/RewardReceipt.svelte';
	const rewardProgram = $derived(ops.data.rewardProgram);

	const activeId = 'DEMO-FAN-1';
	const fan = $derived(ops.data.members.find((member) => member.id === activeId));
	const ranking = $derived(fanRanking());
	let selectedCost = $state(0);
	let requestId = $state('');
	let issuing = $state(false);
	let error = $state('');
	let issuedId = $state('');
	const selectedReward = $derived(rewardProgram.find((reward) => reward.points === selectedCost));
	const issued = $derived(ops.data.rewardReceipts.find((receipt) => receipt.id === issuedId));
	const receipts = $derived(ops.data.rewardReceipts.filter((receipt) => receipt.memberId === activeId).toReversed());

	async function confirmRedemption() {
		if (!account.current) return;
		if (issuing || !selectedReward) return;
		issuing = true;
		error = '';
		try {
			const receipt = await redeemReward(activeId, selectedCost, requestId);
			issuedId = receipt.id;
			selectedCost = 0;
		} catch (e) { error = (e as Error).message; }
		finally { issuing = false; }
	}
</script>

<svelte:head><title>HERCO Points | Fan rewards</title></svelte:head>

{#if account.current}
<section class="section wrap stack">
	<p class="eyebrow">HERCO fan community</p>
	<h1>HERCO Points</h1>
	<p class="muted">See your points, track reward progress and explore the fan ranking.</p>
	{#if error}<p class="error" role="alert">{error}</p>{/if}
	{#if fan}
		<div class="card stack">
			<p class="eyebrow">Your fan account</p>
			<h2>{fan.name}</h2>
			<p class="points">{pointBalance(fan.id)} <span class="small muted">HERCO Points</span></p>
		</div>
		{#if selectedReward}
			<div class="card stack" role="group" aria-label="Confirm reward redemption">
				<h3>Redeem {selectedReward.name}?</h3>
				{#if selectedReward.scope}<p>{selectedReward.scope}</p>{/if}
				<p>{selectedCost.toLocaleString('en-PH')} points will be deducted. Your remaining balance will be {(pointBalance(activeId) - selectedCost).toLocaleString('en-PH')} points.</p>
				<div class="row">
					<button class="btn sm" disabled={issuing || pointBalance(activeId) < selectedCost} onclick={confirmRedemption}>{issuing ? 'Issuing AR…' : 'Confirm redemption'}</button>
					<button class="btn sm ghost" disabled={issuing} onclick={() => (selectedCost = 0)}>Cancel</button>
				</div>
			</div>
		{/if}
		{#if issued}
			<div class="stack" role="status"><p>Reward redeemed. Your AR is ready.</p><RewardReceipt receipt={issued} /></div>
		{/if}
		<div class="stack">
			<p class="eyebrow">HERCO Rewards Program</p>
			<h2>Your support, rewarded</h2>
			<p class="muted">Earn points and claim free rewards and services.</p>
			<div class="cols">
			{#each rewardProgram as reward (reward.points)}
				{@const reached = pointBalance(fan.id) >= reward.points}
				<div class="card stack" class:reward-reached={reached}>
					<p class="eyebrow">{reward.points.toLocaleString('en-PH')} points</p>
					<h3>{reward.name}</h3>
					{#if reward.scope}<p class="muted">{reward.scope}</p>{/if}
					<progress max={reward.points} value={Math.min(pointBalance(fan.id), reward.points)} aria-label={reward.name + ' ' + (reward.scope ?? '') + ' progress'}></progress>
					<p class="small" class:muted={!reached}>{reached ? 'Points target reached' : (reward.points - pointBalance(fan.id)).toLocaleString('en-PH') + ' more points to reach this reward'}</p>
					<button class="btn sm" disabled={!reached || issuing} onclick={() => { selectedCost = reward.points; requestId = crypto.randomUUID(); error = ''; issuedId = ''; }}>Redeem reward</button>
				</div>
			{/each}
			</div>
		</div>
		{#if receipts.length}
			<div class="card stack">
				<h3>Your reward ARs</h3>
				{#each receipts as receipt (receipt.id)}
					<details><summary>{receipt.reward} · {receipt.cost.toLocaleString('en-PH')} points · {receipt.status === 'claimed' ? 'Claimed' : 'Ready to claim'}</summary><RewardReceipt {receipt} /></details>
				{/each}
			</div>
		{/if}
		<div class="card stack">
			<h3>Your points activity</h3>
			{#each ops.data.points.filter((entry) => entry.memberId === fan.id).toReversed() as entry (entry.id)}
				<div class="ranking-row"><div>{entry.reason}<p class="muted small">{new Date(entry.at).toLocaleDateString('en-PH', { timeZone: 'Asia/Manila' })}</p></div><b>{entry.amount > 0 ? '+' : ''}{entry.amount}</b></div>
			{:else}<p class="muted">Your HERCO Points activity will appear here.</p>{/each}
		</div>
	{/if}
	<div class="card stack">
		<h3>Rewards ranking</h3>
		<p class="small muted">Ranked by current HERCO Points. The named sample accounts are fictional.</p>
		{#each ranking as member, index (member.id)}
			<div class="ranking-row" class:current={member.id === activeId}>
				<div class="row"><b class="rank">#{index + 1}</b><span>{member.name}{member.id === activeId ? ' (You)' : ''}</span></div>
				<strong>{pointBalance(member.id)} points</strong>
			</div>
			{/each}
		</div>
</section>
{:else}
	<section class="section wrap points-intro">
		<div class="stack points-welcome">
			<h1>HERCO Points</h1>
			<p class="muted">Sign in to see your balance, redeem rewards, and check what’s ready to claim.</p>
			<div><a class="btn" href={resolve('/account')}>Sign in to HERCO Points</a></div>
		</div>
		<aside class="card stack reward-preview" aria-labelledby="reward-preview-title">
			<h2 id="reward-preview-title">Rewards to work toward</h2>
			<ul>
				{#each rewardProgram.toSorted((a, b) => a.points - b.points) as reward (reward.points)}
					<li><span>{reward.name}{#if reward.scope} · {reward.scope}{/if}</span><strong>{reward.points.toLocaleString('en-PH')} pts</strong></li>
				{/each}
			</ul>
		</aside>
	</section>
{/if}

<style>
	.points-intro { display: grid; gap: clamp(20px, 5vw, 60px); align-items: center; }
	.points-welcome { padding-block: 12px; }
	.points-welcome h1 { font-size: clamp(2.9rem, 7vw, 5.4rem); }
	.points-welcome p { max-width: 42ch; }
	.reward-preview { padding: clamp(16px, 3vw, 26px); border-top: 4px solid var(--accent); }
	.reward-preview h2 { font-size: clamp(1.6rem, 3vw, 2.25rem); }
	.reward-preview ul { list-style: none; margin: 0; padding: 0; }
	.reward-preview li { display: flex; justify-content: space-between; gap: 8px 16px; flex-wrap: wrap; padding-block: 12px; border-top: 1px solid var(--line); }
	.reward-preview li strong { color: var(--accent); white-space: nowrap; }
	@media (min-width: 760px) {
		.points-intro { grid-template-columns: minmax(0, 1.2fr) minmax(0, 1fr); }
	}
	.ranking-row { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 16px; padding: 12px; border-bottom: 1px solid var(--line); }
	.current { background: var(--panel-2); border-radius: 6px; }
	.rank { color: var(--accent); min-width: 32px; }
	.points { font: italic 800 2.6rem var(--display); }

	progress { width: 100%; height: 12px; accent-color: var(--accent); }
	.reward-reached { border-color: var(--ok); }
	.reward-reached > .small { color: var(--ok); }
	summary { cursor: pointer; padding-block: 12px; }
</style>
