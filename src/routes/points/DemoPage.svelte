<script lang="ts">
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { resolve } from '$app/paths';
	import { account } from '#lib/demo/account.svelte.ts';
	import { ops, fanRanking, pointBalance, redeemReward, rewardStatus } from '#lib/demo/operations.svelte.ts';
	import RewardReceipt from '#lib/shared/RewardReceipt.svelte';
	import RewardHeading from '#lib/shared/RewardHeading.svelte';
	const rewardProgram = $derived(ops.data.rewardProgram);

	const activeId = $derived(account.current?.id ?? '');
	const fan = $derived(ops.data.members.find((member) => member.id === activeId));
	const ranking = $derived(fanRanking());
	const topRankCount = 10;
	const ownRank = $derived(ranking.findIndex(member => member.id === activeId) + 1);
	let selectedCost = $state(0);
	let requestId = $state('');
	let issuing = $state(false);
	let error = $state('');
	let issuedId = $state('');
	const selectedReward = $derived(rewardProgram.find((reward) => reward.points === selectedCost));
	const issued = $derived(ops.data.rewardReceipts.find((receipt) => receipt.id === issuedId && receipt.memberId === activeId));
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
	<div class="points-layout">
		<div class="stack">
			{#if error}<p class="error" role="alert">{error}</p>{/if}
			{#if fan}
				<div class="card stack">
					<p class="eyebrow">Your fan account</p>
					<div class="fan-account-summary">
						<h2>{fan.name}</h2>
						<p class="points">{pointBalance(fan.id)} <span class="small muted">HERCO Points</span></p>
					</div>
				</div>
				{#if selectedReward}
					<div class="card stack" role="group" aria-label="Confirm reward redemption">
						<h3>Redeem {selectedReward.name}?</h3>
						{#if selectedReward.scope}<p>{selectedReward.scope}</p>{/if}
						<p>{selectedCost.toLocaleString('en-PH')} points will be deducted. Your remaining balance will be {(pointBalance(activeId) - selectedCost).toLocaleString('en-PH')} points.</p>
						<div class="row">
							<button class="btn sm" disabled={issuing || pointBalance(activeId) < selectedCost} onclick={confirmRedemption}><ActionIcon name="check" />{issuing ? 'Submitting…' : 'Confirm redemption'}</button>
							<button class="btn sm ghost" disabled={issuing} onclick={() => (selectedCost = 0)}><ActionIcon name="close" />Cancel</button>
						</div>
					</div>
				{/if}
				{#if issued}
					<div class="stack" role="status"><p>Redemption status: {rewardStatus(issued)}</p><RewardReceipt receipt={issued} /></div>
				{/if}
				<div class="stack">
					<p class="eyebrow">HERCO Rewards Program</p>
					<h2>Your support, rewarded</h2>
					<p class="muted">Earn points and claim free rewards and services.</p>
					<div class="cols">
					{#each rewardProgram as reward (reward.points)}
						{@const reached = pointBalance(fan.id) >= reward.points}
						<div class="card stack" class:reward-reached={reached}>
							<RewardHeading name={reward.name} points={reward.points} />
							{#if reward.scope}<p class="muted">{reward.scope}</p>{/if}
							<progress max={reward.points} value={Math.min(pointBalance(fan.id), reward.points)} aria-label={reward.name + ' ' + (reward.scope ?? '') + ' progress'}></progress>
							<p class="small" class:muted={!reached}>{reached ? 'Points target reached' : (reward.points - pointBalance(fan.id)).toLocaleString('en-PH') + ' more points to reach this reward'}</p>
							<button class="btn sm" disabled={!reached || issuing} onclick={() => { selectedCost = reward.points; requestId = crypto.randomUUID(); error = ''; issuedId = ''; }}><ActionIcon name="gift" />Redeem reward</button>
						</div>
					{/each}
					</div>
				</div>
				{#if receipts.length}
					<div class="card stack">
						<h3>Your reward ARs</h3>
						{#each receipts as receipt (receipt.id)}
							<details><summary>{receipt.reward} · {receipt.cost.toLocaleString('en-PH')} points · {rewardStatus(receipt)}</summary><RewardReceipt {receipt} /></details>
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
		</div>
		<aside class="card stack leaderboard" aria-labelledby="leaderboard-title">
			<h3 id="leaderboard-title">Rewards ranking</h3>
			<p class="small muted">Ranked by current HERCO Points. The named sample accounts are fictional.</p>
			{#each ranking.slice(0, topRankCount) as member, index (member.id)}
				<div class="ranking-row" class:current={member.id === activeId}>
					<b class="rank">#{index + 1}</b><span class="member-name" title={member.name}>{member.name}</span>
					<strong>{pointBalance(member.id)} points</strong>
				</div>
			{/each}
			{#if fan && ownRank > topRankCount}
				<div class="ranking-row current own-ranking" aria-label="Your ranking">
					<b class="rank">#{ownRank}</b><span class="member-name" title={fan.name}>{fan.name} <span class="small muted">(You)</span></span>
					<strong>{pointBalance(fan.id)} points</strong>
				</div>
			{/if}
		</aside>
	</div>
</section>
{:else}
	<section class="section wrap points-intro">
		<div class="stack points-welcome">
			<h1>HERCO Points</h1>
			<p class="muted">Sign in to see your balance, redeem rewards, and check what’s ready to claim.</p>
			<div><a class="btn" href={resolve('/account')}><ActionIcon name="login" />Sign in to HERCO Points</a></div>
		</div>
		<aside class="card stack reward-preview" aria-labelledby="reward-preview-title">
			<h2 id="reward-preview-title">Rewards to work toward</h2>
			<ul>
				{#each rewardProgram.toSorted((a, b) => a.points - b.points) as reward (reward.points)}
					<li><RewardHeading name={reward.name} points={reward.points} tag="span" />{#if reward.scope}<span class="small muted">{reward.scope}</span>{/if}</li>
				{/each}
			</ul>
		</aside>
	</section>
{/if}

<style>
	.points-layout { display: grid; gap: 20px; align-items: start; }
	.leaderboard { border-top: 4px solid var(--accent); border-radius: 12px; padding: 20px; box-shadow: 0 4px 12px var(--card-shadow); }
	@media (min-width: 960px) {
		.points-layout { grid-template-columns: minmax(0, 2fr) minmax(280px, 1fr); gap: 24px; }
		.leaderboard { position: sticky; top: 80px; max-height: calc(100vh - 100px); overflow: auto; }
	}
	.points-intro { display: grid; gap: clamp(20px, 5vw, 60px); align-items: center; }
	.points-welcome { padding-block: 12px; }
	.points-welcome h1 { font-size: clamp(2.9rem, 7vw, 5.4rem); }
	.points-welcome p { max-width: 42ch; }
	.reward-preview { padding: clamp(16px, 3vw, 26px); border-top: 4px solid var(--accent); }
	.reward-preview h2 { font-size: clamp(1.6rem, 3vw, 2.25rem); }
	.reward-preview ul { list-style: none; margin: 0; padding: 0; }
	.reward-preview li { display: grid; gap: 4px; padding-block: 12px; border-top: 1px solid var(--line); }
	@media (min-width: 760px) {
		.points-intro { grid-template-columns: minmax(0, 1.2fr) minmax(0, 1fr); }
	}
	.ranking-row { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 16px; padding: 12px; border-bottom: 1px solid var(--line); }
	.current { background: var(--panel-2); border-radius: 6px; }
	.own-ranking { margin-top: .35rem; }
	.leaderboard .ranking-row { display: grid; grid-template-columns: auto minmax(0, 1fr) auto; gap: 8px; }
	.leaderboard .member-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.leaderboard strong { white-space: nowrap; }
	.rank { color: var(--accent); }
	.points { font: italic 800 2.6rem var(--display); }
	.fan-account-summary { display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: baseline; gap: .75rem; }
	.fan-account-summary h2 { overflow-wrap: anywhere; }
	.fan-account-summary .points { text-align: right; white-space: nowrap; font-size: clamp(1.5rem, 4vw, 2.6rem); }

	progress { width: 100%; height: 12px; accent-color: var(--accent); }
	.reward-reached { border-color: var(--ok); }
	.reward-reached > .small { color: var(--ok); }
	summary { cursor: pointer; padding-block: 12px; }
</style>
