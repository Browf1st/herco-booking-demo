<script lang="ts">
	import { fmtDate, upcoming } from './dates';
	import { dayStatus, spotsLeft } from './store.svelte';

	// Admin mode lets full and blocked days be opened, customers can only pick open days.
	let { value, onpick, admin = false }: { value: string; onpick: (date: string) => void; admin?: boolean } = $props();

	const labels = { closed: 'Closed', blocked: 'Blocked', full: 'Full' };
</script>

<div class="strip">
	{#each upcoming() as d (d)}
		{@const status = dayStatus(d)}
		<button
			type="button"
			class:on={value === d}
			data-status={status}
			disabled={status === 'closed' || (!admin && status !== 'open')}
			onclick={() => onpick(d)}
		>
			<small>{fmtDate(d, { weekday: 'short' })}</small>
			<b>{fmtDate(d, { day: 'numeric' })}</b>
			<small>{fmtDate(d, { month: 'short' })}</small>
			<em>{status === 'open' ? `${spotsLeft(d)} left` : labels[status]}</em>
		</button>
	{/each}
</div>

<style>
	.strip {
		display: flex;
		gap: 8px;
		overflow-x: auto;
		padding-bottom: 8px;
		scroll-snap-type: x proximity;
	}

	button {
		display: grid;
		flex: 0 0 76px;
		justify-items: center;
		padding: 10px 4px;
		background: var(--panel);
		border: 1px solid var(--line);
		border-radius: 6px;
		color: var(--text);
		font: inherit;
		line-height: 1.2;
		cursor: pointer;
		scroll-snap-align: start;
	}

	small {
		color: var(--muted);
		font-size: 0.75rem;
		text-transform: uppercase;
	}

	b {
		font: italic 800 2rem var(--display);
	}

	em {
		margin-top: 4px;
		color: var(--ok);
		font: 700 0.8rem var(--display);
		letter-spacing: 0.08em;
		text-transform: uppercase;
	}

	[data-status='full'] em,
	[data-status='blocked'] em {
		color: var(--bad);
	}

	[data-status='closed'] em {
		color: var(--muted);
	}

	button:disabled {
		opacity: 0.45;
		cursor: not-allowed;
	}

	.on {
		background: var(--panel-2);
		border-color: var(--accent);
		box-shadow: inset 0 -4px 0 var(--accent);
	}
</style>
