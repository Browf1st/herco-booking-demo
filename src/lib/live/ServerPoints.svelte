<script lang="ts">
 import ActionIcon from '../shared/ActionIcon.svelte';
 import { resolve } from '$app/paths';
 import { onMount } from 'svelte';
 import RewardReceipt from '../shared/RewardReceipt.svelte';
 import RewardHeading from '../shared/RewardHeading.svelte';
 import { rewardStatus, type RewardReceipt as Receipt } from '../shared/reward-receipt';
 type Reward = {id:string;label:string;scope:string;cost:number};
 type Points = {memberId:string;memberName:string;balance:number;ownRank:number;ranking:{position:number;name:string;balance:number;isCurrent:boolean}[];rewards:Reward[];ledger:{id:number;amount:number;reason:string;created_at:string}[];receipts:{id:string;reference:string;reward_label:string;reward_scope:string;cost:number;balance_after:number;member_name:string;created_at:string;approved_at:string|null;claimed_at:string|null}[]};
 let points=$state<Points>(); let previewRewards=$state<Reward[]>([]); let loading=$state(true); let error=$state(''); let notice=$state('');
 let selectedId=$state(''); let requestId=$state(''); let issuing=$state(false); let issuedId=$state('');
 const activeId=$derived(points?.memberId??'');
 const fan=$derived(points?{id:points.memberId,name:points.memberName}:null);
 const rewardProgram=$derived((points?.rewards??previewRewards).map(r=>({...r,name:r.label,points:r.cost})));
 const selectedReward=$derived(rewardProgram.find(r=>r.id===selectedId)); const selectedCost=$derived(selectedReward?.points??0);
 const topRankCount=10; const ownRank=$derived(points?.ownRank??0);
 const ranking=$derived((points?.ranking??[]).map(r=>({...r,id:r.isCurrent?activeId:'rank-'+r.position})));
 const pointBalance=(id:string)=>id===activeId?(points?.balance??0):(ranking.find(r=>r.id===id)?.balance??0);
 const ledger=$derived((points?.ledger??[]).map(e=>({...e,at:e.created_at,memberId:activeId})));
 const receipts=$derived((points?.receipts??[]).map((r):Receipt=>({id:r.id,reference:r.reference||r.id,memberId:activeId,memberName:r.member_name||points?.memberName||'HERCO member',reward:r.reward_label+(r.reward_scope?' · '+r.reward_scope:''),cost:r.cost,balanceBefore:(r.balance_after??0)+r.cost,balanceAfter:r.balance_after??0,at:r.created_at,status:r.claimed_at?'claimed':r.approved_at?'approved':'pending',claimedAt:r.claimed_at??undefined})));
 const issued=$derived(receipts.find(r=>r.id===issuedId));
 async function load(){loading=true;error='';try{const [account,rewards]=await Promise.all([fetch(resolve('/api/points')),fetch(resolve('/api/points/rewards'))]);if(rewards.ok)previewRewards=await rewards.json();if(account.status===401){points=undefined;return;}if(!account.ok)throw new Error();points=await account.json();}catch{error='HERCO Points are temporarily unavailable. Please try again.';}finally{loading=false;}}
 async function confirmRedemption(){if(issuing||!selectedReward)return;issuing=true;error='';try{const response=await fetch(resolve('/api/points'),{method:'POST',headers:{'content-type':'application/json',accept:'application/json'},body:JSON.stringify({rewardId:selectedReward.id,requestId})});const result=await response.json().catch(()=>null);if(!response.ok)throw new Error(result?.message??'Could not confirm your redemption. Try again.');issuedId=result.id;selectedId='';notice='Reward requested. The shop will review your redemption.';await load();}catch(failure){error=failure instanceof Error?failure.message:'Could not reach HERCO Points. Try again.';}finally{issuing=false;}}
 onMount(()=>{void load();});
</script>
<svelte:head><title>HERCO Points | Fan rewards</title></svelte:head>
{#if loading}<section class="section wrap"><p role="status">Loading HERCO Points…</p></section>{:else if error && !points}<section class="section wrap stack"><p role="alert">{error}</p><div><button class="btn ghost" onclick={load}>Try again</button></div></section>{:else}


{#if points}
<section class="section wrap stack points-page">
	<p class="eyebrow">HERCO fan community</p>
	<h1>HERCO Points</h1>
	<p class="muted">See your points, track reward progress and explore the fan ranking.</p>
	<div class="points-layout">
		<div class="stack">
			{#if error}<p class="error" role="alert">{error}</p>{/if}{#if notice}<p role="status">{notice}</p>{/if}
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
							<button class="btn sm ghost" disabled={issuing} onclick={() => (selectedId = '')}><ActionIcon name="close" />Cancel</button>
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
					{#each rewardProgram as reward (reward.id)}
						{@const reached = pointBalance(fan.id) >= reward.points}
						<div class="card stack" class:reward-reached={reached}>
							<RewardHeading name={reward.name} points={reward.points} />
							{#if reward.scope}<p class="muted">{reward.scope}</p>{/if}
							<progress max={reward.points} value={Math.min(pointBalance(fan.id), reward.points)} aria-label={reward.name + ' ' + (reward.scope ?? '') + ' progress'}></progress>
							<p class="small" class:muted={!reached}>{reached ? 'Points target reached' : (reward.points - pointBalance(fan.id)).toLocaleString('en-PH') + ' more points to reach this reward'}</p>
							<button class="btn sm" disabled={!reached || issuing} onclick={() => { selectedId = reward.id; requestId = crypto.randomUUID(); error = ''; issuedId = ''; }}><ActionIcon name="gift" />Redeem reward</button>
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
					{#each ledger as entry (entry.id)}
						<div class="ranking-row"><div>{entry.reason}<p class="muted small">{new Date(entry.at).toLocaleDateString('en-PH', { timeZone: 'Asia/Manila' })}</p></div><b>{entry.amount > 0 ? '+' : ''}{entry.amount}</b></div>
					{:else}<p class="muted">Your HERCO Points activity will appear here.</p>{/each}
				</div>
			{/if}
		</div>
		<aside class="card stack leaderboard" aria-labelledby="leaderboard-title">
			<h3 id="leaderboard-title">Rewards ranking</h3>
			<p class="small muted">Ranked by current HERCO Points. Members choose whether to share their ranking name.</p>
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
	<section class="section wrap points-intro points-page">
		<div class="stack points-welcome">
			<h1>HERCO Points</h1>
			<p class="muted">Sign in to see your balance, redeem rewards, and check what’s ready to claim.</p>
			<div><a class="btn" href={resolve('/account')}><ActionIcon name="login" />Sign in to HERCO Points</a></div>
		</div>
		<aside class="card stack reward-preview" aria-labelledby="reward-preview-title">
			<h2 id="reward-preview-title">Rewards to work toward</h2>
			<ul>
				{#each rewardProgram.toSorted((a, b) => a.points - b.points) as reward (reward.id)}
					<li><RewardHeading name={reward.name} points={reward.points} tag="span" />{#if reward.scope}<span class="small muted">{reward.scope}</span>{/if}</li>
				{:else}
					<li class="muted">Rewards will appear here once the shop publishes them.</li>
				{/each}
			</ul>
		</aside>
	</section>
{/if}


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
	/* Owner asked for smaller type here (2026-11-20): titles about 32-40px instead of up to 99px. */
	.points-page h1 { font-size: clamp(2rem, 5vw, 2.5rem); line-height: 1.05; }
	.points-page h2 { font-size: clamp(1.25rem, 3vw, 1.5rem); line-height: 1.15; }
	.points-page h3 { font-size: 1.1rem; line-height: 1.2; }
	.points-welcome p { max-width: 42ch; }
	.reward-preview { padding: clamp(16px, 3vw, 26px); border-top: 4px solid var(--accent); }
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
	.points { font: italic 800 1.8rem var(--display); }
	.fan-account-summary { display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: baseline; gap: .75rem; }
	.fan-account-summary h2 { overflow-wrap: anywhere; }
	.fan-account-summary .points { text-align: right; white-space: nowrap; font-size: clamp(1.4rem, 4vw, 1.8rem); }

	progress { width: 100%; height: 12px; accent-color: var(--accent); }
	.reward-reached { border-color: var(--ok); }
	.reward-reached > .small { color: var(--ok); }
	summary { cursor: pointer; padding-block: 12px; }
</style>
