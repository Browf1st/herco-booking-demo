<script lang="ts">
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { asset } from '$app/paths';
	import { rewardStatus, type RewardReceipt } from '../shared/reward-receipt';
	let { receipt }: { receipt: RewardReceipt } = $props();
	const logo = asset('photos/logo.png');
	const date = (value: string) => new Date(value).toLocaleString('en-PH', { timeZone: 'Asia/Manila', hour12: true });
	const rows = $derived([
		['Redeemed by', receipt.memberName],
		['Requested (PH time)', date(receipt.at)],
		['Points redeemed', receipt.cost.toLocaleString('en-PH')],
		['Remaining points', receipt.balanceAfter.toLocaleString('en-PH')],
		['Status', rewardStatus(receipt)],
		...(receipt.claimedAt ? [['Claimed (PH time)', date(receipt.claimedAt)]] : []),
		...(receipt.claimedBy ? [['Claim recorded by', receipt.claimedBy]] : [])
	]);
	let downloading = $state(false);
	let downloadError = $state('');

	async function download() {
		downloading = true;
		downloadError = '';
		try {
			const mark = new Image();
			mark.src = logo;
			await mark.decode();
			const canvas = document.createElement('canvas');
			canvas.width = 1000;
			canvas.height = 1400;
			const context = canvas.getContext('2d');
			if (!context) throw new Error('Canvas unavailable.');
			context.fillStyle = '#f4f6fa';
			context.fillRect(0, 0, canvas.width, canvas.height);
			context.fillStyle = '#171e29';
			context.fillRect(0, 0, canvas.width, 200);
			context.fillStyle = '#b81034';
			context.fillRect(0, 200, canvas.width, 8);
			context.fillStyle = '#fff';
			context.fillRect(48, 42, 116, 116);
			const scale = Math.min(100 / mark.naturalWidth, 100 / mark.naturalHeight);
			const width = mark.naturalWidth * scale;
			const height = mark.naturalHeight * scale;
			context.drawImage(mark, 106 - width / 2, 100 - height / 2, width, height);
			context.font = 'bold 38px sans-serif';
			context.fillText('HERCO DETAILING GARAGE', 195, 94);
			context.font = '23px sans-serif';
			context.fillText('REWARDS ACKNOWLEDGMENT RECEIPT', 195, 134);

			context.fillStyle = '#171e29';
			context.font = 'bold 38px sans-serif';
			const rewardLines = wrapText(context, receipt.reward, 880);
			let y = 276;
			for (const line of rewardLines) {
				context.fillText(line, 60, y);
				y += 46;
			}
			context.fillStyle = '#526074';
			context.font = '22px monospace';
			context.fillText(receipt.reference, 60, y + 8);
			y += 70;
			for (const [label, value] of rows) {
				context.fillStyle = '#526074';
				context.font = '21px sans-serif';
				context.fillText(label, 60, y);
				context.fillStyle = '#171e29';
				context.font = 'bold 28px sans-serif';
				for (const line of wrapText(context, value, 880)) {
					y += 35;
					context.fillText(line, 60, y);
				}
				y += 49;
			}
			const output = document.createElement('canvas');
			output.width = canvas.width;
			output.height = y + 25;
			const outputContext = output.getContext('2d');
			if (!outputContext || output.height > canvas.height) throw new Error('Receipt exceeds image size.');
			outputContext.drawImage(canvas, 0, 0);
			const blob = await new Promise<Blob | null>(resolve => output.toBlob(resolve, 'image/png'));
			if (!blob) throw new Error('Could not generate receipt image.');
			const url = URL.createObjectURL(blob);
			const link = document.createElement('a');
			link.href = url;
			link.download = receipt.reference + '.png';
			link.click();
			setTimeout(() => URL.revokeObjectURL(url), 1000);
		} catch {
			downloadError = 'Could not download the receipt image. Please try again.';
		} finally {
			downloading = false;
		}
	}

	function wrapText(context: CanvasRenderingContext2D, value: string, width: number) {
		const lines: string[] = [];
		let line = '';
		for (const character of value) {
			if (context.measureText(line + character).width > width) {
				const space = line.lastIndexOf(' ');
				lines.push(space > 0 ? line.slice(0, space) : line);
				line = space > 0 ? line.slice(space + 1) : '';
			}
			line += character;
		}
		lines.push(line);
		return lines;
	}
</script>

<article class="receipt">
	<header class="receipt-header">
		<img src={logo} alt="HERCO" width="56" height="56" />
		<div><b>HERCO Detailing Garage</b><p class="small">Rewards acknowledgment receipt</p></div>
	</header>
	<div class="receipt-body stack">
		<h3>{receipt.reward}</h3>
		<p class="reference">{receipt.reference}</p>
		<dl>
			{#each rows as [label, value] (label)}
				<div><dt>{label}</dt><dd>{value}</dd></div>
			{/each}
		</dl>
		{#if receipt.status === 'pending'}
			<p class="small muted">Your request is waiting for HERCO to approve it.</p>
		{:else if receipt.status !== 'claimed'}
			<p class="small muted">Present this AR at HERCO to claim your reward.</p>
		{/if}
		{#if downloadError}<p class="error" role="alert">{downloadError}</p>{/if}
		<div><button type="button" class="btn sm ghost" disabled={downloading} onclick={download}><ActionIcon name="download" />{downloading ? 'Preparing image…' : 'Download AR (PNG)'}</button></div>
	</div>
</article>

<style>
	.receipt { overflow: hidden; border: 1px solid var(--line); border-radius: .65rem; background: var(--bg); }
	.receipt-header { display: flex; gap: .85rem; align-items: center; padding: 1rem; background: #171e29; color: white; border-bottom: 4px solid #b81034; }
	.receipt-header img { object-fit: contain; padding: .25rem; border-radius: .35rem; background: white; }
	.receipt-body { padding: 1rem; }
	.reference { overflow-wrap: anywhere; font-family: monospace; font-size: .85rem; color: var(--muted); }
	dl { display: grid; gap: .45rem; margin: 0; }
	dl div { display: flex; flex-wrap: wrap; gap: .25rem .75rem; justify-content: space-between; }
	dt { color: var(--muted); }
	dd { margin: 0; font-weight: 600; overflow-wrap: anywhere; min-width: 0; }
</style>
