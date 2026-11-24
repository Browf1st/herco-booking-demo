<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// Header Account menu, the same button for everyone. Signed in: avatar and chevron, and the dropdown shows the name,
	// email, role, Account settings, the theme choice and Sign out. Signed out: "SIGN IN" and chevron, and the dropdown
	// has Sign in, Create account and the theme choice.
	import { onMount } from 'svelte';
	import ActionIcon from './ActionIcon.svelte';
	import MoreIcons from './MoreIcons.svelte';
	import type { MenuUser } from './account-menu';
	import { initials } from './report-ui';
	import { currentTheme, setTheme, themeOptions, THEME_EVENT, type ThemeChoice } from './theme';

	let { user = null, settingsHref, signingOut = false, onsignout }: {
		user?: MenuUser | null; settingsHref: string; signingOut?: boolean; onsignout: () => void;
	} = $props();
	let open = $state(false);
	let theme = $state<ThemeChoice>('system');
	let root = $state<HTMLElement>();
	let trigger = $state<HTMLButtonElement>();
	const icons = { system: 'system', light: 'sun', dark: 'moon' } as const;

	function close(focusTrigger = false) { open = false; if (focusTrigger) trigger?.focus(); }
	onMount(() => {
		const sync = () => { theme = currentTheme(); };
		sync();
		window.addEventListener(THEME_EVENT, sync);
		// Another tab changed the theme: the page applies it first, then this menu catches up.
		window.addEventListener('storage', sync);
		return () => { window.removeEventListener(THEME_EVENT, sync); window.removeEventListener('storage', sync); };
	});
</script>

<svelte:window onclick={(event) => { if (open && root && event.target instanceof Node && !root.contains(event.target)) close(); }}
	onkeydown={(event) => { if (event.key === 'Escape' && open) close(true); }} />

<div class="account" bind:this={root} onfocusout={(event) => { if (open && root && event.relatedTarget instanceof Node && !root.contains(event.relatedTarget)) close(); }}>
	<button type="button" class="trigger" class:signed-out={!user} bind:this={trigger} aria-expanded={open} aria-controls={open ? 'account-panel' : undefined} aria-label={user ? 'Account menu for ' + user.name : undefined} onclick={() => open = !open}>
		{#if user}<span class="avatar" aria-hidden="true">{initials(user.name)}</span>{:else}<span class="label">Sign in</span>{/if}
		<MoreIcons name={open ? 'up' : 'down'} />
	</button>
	{#if open}
		<div class="panel" id="account-panel">
			{#if user}
				<div class="who"><b>{user.name}</b><small>{user.email}</small></div>
				<p class="role">{user.role}</p>
				<a class="row-item" href={settingsHref} onclick={() => close()}>Account settings<MoreIcons name="gear" /></a>
			{:else}
				<a class="row-item" href={settingsHref} onclick={() => close()}>Sign in<ActionIcon name="login" /></a>
				<a class="row-item" href={settingsHref} onclick={() => close()}>Create account<ActionIcon name="add" /></a>
			{/if}
			<hr />
			<p class="role" id="theme-label">Theme</p>
			<div class="themes" role="group" aria-labelledby="theme-label">
				{#each themeOptions as option (option.value)}
					<button type="button" aria-pressed={theme === option.value} onclick={() => setTheme(option.value)}><ActionIcon name={icons[option.value]} />{option.label}</button>
				{/each}
			</div>
			{#if user}
				<hr />
				<button type="button" class="row-item" disabled={signingOut} onclick={() => { close(); onsignout(); }}>{signingOut ? 'Signing out…' : 'Sign out'}<ActionIcon name="logout" /></button>
			{/if}
		</div>
	{/if}
</div>

<style>
	.account { position: relative; flex: none; }
	.trigger { display: flex; align-items: center; justify-content: center; gap: .4rem; min-height: 44px; padding: .2rem .5rem .2rem .25rem; border: 1px solid transparent; border-radius: 99px; background: transparent; color: var(--text); font: inherit; text-align: start; white-space: nowrap; cursor: pointer; }
	.trigger.signed-out { padding-inline: .75rem .5rem; }
	.trigger:hover, .trigger[aria-expanded='true'] { border-color: var(--line); background: var(--panel); }
	.avatar { display: grid; place-items: center; flex: none; width: 2.5rem; height: 2.5rem; border-radius: 50%; background: light-dark(#14213d, #0b1018); color: #fbbf24; font: 800 .9rem var(--body); }
	.who { display: grid; min-width: 0; padding: .1rem .4rem; line-height: 1.25; }
	.who b, .who small { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.who small { color: var(--muted); font-size: .8rem; }
	/* Same type as the nav tabs (display font, bold, capitals), signed in or out. */
	.label { font: 700 1.05rem var(--display); letter-spacing: .1em; text-transform: uppercase; }
	.panel { position: absolute; z-index: 20; inset: calc(100% + .4rem) 0 auto auto; display: grid; gap: .35rem; width: 17rem; padding: .85rem; border: 1px solid var(--line); border-radius: 16px; background: var(--panel); box-shadow: 0 12px 32px var(--card-shadow); }
	.role { text-transform: capitalize; color: var(--muted); font-size: .78rem; font-weight: 600; }
	hr { width: 100%; margin: .25rem 0; border: 0; border-top: 1px solid var(--line); }
	.row-item { display: flex; align-items: center; justify-content: space-between; min-height: 44px; padding: 0 .4rem; border: 0; border-radius: 8px; background: transparent; color: var(--text); font: 800 .95rem var(--body); text-decoration: none; cursor: pointer; }
	.row-item:hover { background: var(--panel-2); }
	.row-item:disabled { opacity: .5; cursor: wait; }
	.themes { display: grid; grid-template-columns: repeat(3, 1fr); gap: 2px; padding: 3px; border-radius: 10px; background: var(--panel-2); }
	.themes button { display: inline-flex; align-items: center; justify-content: center; gap: .3rem; min-height: 40px; padding: 0 .3rem; border: 0; border-radius: 8px; background: transparent; color: var(--text); font: 700 .8rem var(--body); cursor: pointer; }
	.themes button[aria-pressed='true'] { background: var(--accent-fill); color: var(--accent-ink); }
	@media (max-width: 960px) {
		.account { position: static; }
		.panel { inset: 100% 0 auto 0; width: auto; border-radius: 0 0 16px 16px; border-width: 0 0 1px; }
	}
</style>
