<script lang="ts">
	import type { RewardReceipt } from './operations.svelte';
	let { receipt }: { receipt: RewardReceipt } = $props();

	function download() {
		const text = [
			'HERCO DETAILING GARAGE',
			'REWARDS ACKNOWLEDGMENT RECEIPT',
			receipt.reference,
			'Issued ' + new Date(receipt.at).toLocaleString('en-PH', { timeZone: 'Asia/Manila', hour12: true }),
			'Fan ' + receipt.memberName,
			'Reward ' + receipt.reward,
			'Points redeemed ' + receipt.cost,
			'Balance before redemption ' + receipt.balanceBefore,
			'Balance after redemption ' + receipt.balanceAfter,
			'Status ' + receipt.status,
			receipt.claimedAt ? 'Claimed ' + new Date(receipt.claimedAt).toLocaleString('en-PH', { timeZone: 'Asia/Manila', hour12: true }) : 'Present this AR at HERCO to claim your reward.',
			'Local demo receipt'
		].join('\r\n');
		const url = URL.createObjectURL(new Blob([text], { type: 'text/plain;charset=utf-8' }));
		const link = document.createElement('a');
		link.href = url;
		link.download = receipt.reference + '.txt';
		link.click();
		setTimeout(() => URL.revokeObjectURL(url), 1000);
	}
</script>

<div class="receipt stack">
	<p class="eyebrow">HERCO / Reward acknowledgment receipt</p>
	<h3>{receipt.reward}</h3>
	<p class="reference">{receipt.reference}</p>
	<dl>
		<div><dt>Fan</dt><dd>{receipt.memberName}</dd></div>
		<div><dt>Issued</dt><dd>{new Date(receipt.at).toLocaleString('en-PH', { timeZone: 'Asia/Manila', hour12: true })}</dd></div>
		<div><dt>Points redeemed</dt><dd>{receipt.cost.toLocaleString('en-PH')}</dd></div>
		<div><dt>Balance after redemption</dt><dd>{receipt.balanceAfter.toLocaleString('en-PH')}</dd></div>
		<div><dt>Status</dt><dd>{receipt.status === 'claimed' ? 'Claimed' : 'Ready to claim'}</dd></div>
	</dl>
	{#if receipt.claimedAt}
		<p class="small muted">Claimed {new Date(receipt.claimedAt).toLocaleString('en-PH', { timeZone: 'Asia/Manila', hour12: true })}</p>
	{:else}
		<p class="small muted">Present this AR at HERCO to claim your reward.</p>
	{/if}
	<div><button class="btn sm ghost" onclick={download}>Download AR</button></div>
</div>

<style>
	.receipt { padding: 18px; border: 1px dashed var(--line); border-radius: 6px; background: var(--bg); }
	.reference { overflow-wrap: anywhere; font-family: monospace; font-size: 0.85rem; color: var(--muted); }
	dl { display: grid; gap: 8px; margin: 0; }
	dl div { display: flex; flex-wrap: wrap; gap: 8px; justify-content: space-between; }
	dt { color: var(--muted); }
	dd { margin: 0; }
</style>
