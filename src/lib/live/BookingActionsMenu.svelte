<script lang="ts">
	// One red "Actions" menu per customer booking card. It lists only the items allowed for that booking.
	// Closes on a tap outside, Esc, choosing an item, or the phone Back button (like the details sheets).
	import { pushState, replaceState } from '$app/navigation';
	import { page } from '$app/state';
	import ActionIcon from '../shared/ActionIcon.svelte';
	import { menuLabels, type MenuItem } from './booking-menu';

	let { id, items, busy = false, onpick }: { id: string; items: MenuItem[]; busy?: boolean; onpick: (item: MenuItem) => void } = $props();
	const icons = { reschedule: 'calendar', cancel: 'block', withdraw: 'reset', details: 'view' } as const;
	let open = $state(false);
	let root = $state<HTMLDivElement>();
	let trigger = $state<HTMLButtonElement>();

	// history.back() lands later than the next pushState, so it could pop a sheet or another menu opened right after.
	// So: opening while another card's menu entry exists reuses that entry, and picking an item or tapping another
	// card's menu never calls back(); it rewrites the entry in place (the sheet then takes it over).
	function show() {
		open = true;
		if (page.state.actionsMenu) replaceState('', { actionsMenu: id });
		else pushState('', { actionsMenu: id });
	}
	// Closing by hand also removes the history entry added on open, so Back keeps its normal job.
	function hide(refocus = false, keepEntry = false) {
		if (!open) return;
		open = false;
		if (!keepEntry && page.state.actionsMenu === id) history.back();
		if (refocus) trigger?.focus();
	}
	// Phone Back removed the entry: close the menu.
	$effect(() => { if (open && page.state.actionsMenu !== id) open = false; });
	function pick(item: MenuItem) {
		hide(false, true);
		// "View details" turns this entry into the sheet's own entry; other items just clear it.
		if (item !== 'details' && page.state.actionsMenu === id) replaceState('', {});
		onpick(item);
	}
	function tapOutside(target: Node) {
		if (!open || !root || root.contains(target)) return;
		const otherMenu = target instanceof Element && target.closest('.menu');
		hide(false, !!otherMenu);
	}
</script>

<svelte:window
	onpointerdown={(event) => tapOutside(event.target as Node)}
	onkeydown={(event) => { if (open && event.key === 'Escape') { event.preventDefault(); hide(true); } }}
/>

<div class="menu" bind:this={root}>
	<button type="button" class="trigger" bind:this={trigger} aria-haspopup="menu" aria-expanded={open} onclick={() => open ? hide() : show()}>
		Actions <ActionIcon name="down" />
	</button>
	{#if open}
		<ul role="menu" aria-label="Booking actions">
			{#each items as item (item)}
				<li role="none"><button type="button" role="menuitem" class:danger={item === 'cancel'} disabled={busy && item === 'withdraw'} onclick={() => pick(item)}><ActionIcon name={icons[item]} />{menuLabels[item]}</button></li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.menu { position: relative; }
	.trigger { display: inline-flex; align-items: center; gap: .4rem; min-height: 2.75rem; padding: 0 1rem; border: 1px solid var(--accent); border-radius: 8px; background: var(--accent); color: #fff; font: 700 .9rem var(--body); cursor: pointer; }
	.trigger:focus-visible, button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
	ul { position: absolute; inset: calc(100% + .3rem) auto auto 0; z-index: 5; display: grid; gap: .15rem; width: max-content; min-width: 100%; max-width: min(16rem, calc(100vw - 2rem)); margin: 0; padding: .3rem; list-style: none; border: 1px solid var(--bad-line); border-radius: 10px; background: var(--panel); box-shadow: 0 6px 18px var(--card-shadow); }
	li button { display: flex; align-items: center; gap: .55rem; width: 100%; min-height: 2.75rem; padding: 0 .7rem; border: 0; border-radius: 6px; background: transparent; color: var(--text); font: 650 .9rem var(--body); text-align: start; cursor: pointer; }
	li button:hover:not(:disabled) { background: var(--bad-bg); color: var(--accent); }
	.danger { color: var(--bad); }
</style>
