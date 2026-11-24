<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// Header Account menu for everyone signed in: avatar, name, email and a dropdown with Account settings,
	// the theme choice and Sign out. Signed-out visitors get a small sun/moon theme button instead.
	import { onMount } from 'svelte';
	import ActionIcon from './ActionIcon.svelte';
	import MoreIcons from './MoreIcons.svelte';
	import { oppositeTheme, type MenuUser } from './account-menu';
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
	const systemIsDark = () => matchMedia('(prefers-color-scheme: dark)').matches;

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

{#if user}
	<div class="account" bind:this={root} onfocusout={(event) => { if (open && root && event.relatedTarget instanceof Node && !root.contains(event.relatedTarget)) close(); }}>
		<button type="button" class="trigger" bind:this={trigger} aria-expanded={open} aria-controls={open ? 'account-panel' : undefined} aria-label={'Account menu for ' + user.name} onclick={() => open = !open}>
			<span class="avatar" aria-hidden="true">{initials(user.name)}</span>
			<span class="who"><b>{user.name}</b><small>{user.email || user.role}</small></span>
			<span class="label">Account <MoreIcons name={open ? 'up' : 'down'} /></span>
		</button>
		{#if open}
			<div class="panel" id="account-panel">
				<p class="role">{user.role}</p>
				<a class="row-item" href={settingsHref} onclick={() => close()}>Account settings<MoreIcons name="gear" /></a>
				<hr />
				<p class="role" id="theme-label">Theme</p>
				<div class="themes" role="group" aria-labelledby="theme-label">
					{#each themeOptions as option (option.value)}
						<button type="button" aria-pressed={theme === option.value} onclick={() => setTheme(option.value)}><ActionIcon name={icons[option.value]} />{option.label}</button>
					{/each}
				</div>
				<hr />
				<button type="button" class="row-item" disabled={signingOut} onclick={() => { close(); onsignout(); }}>{signingOut ? 'Signing out…' : 'Sign out'}<ActionIcon name="logout" /></button>
			</div>
		{/if}
	</div>
{:else}
	{@const next = oppositeTheme(theme, typeof matchMedia === 'function' && systemIsDark())}
	<button type="button" class="theme-button" aria-label={'Switch to ' + next + ' theme'} onclick={() => setTheme(next)}><ActionIcon name={next === 'dark' ? 'moon' : 'sun'} /></button>
{/if}

<style>
	.account { position: relative; flex: none; }
	.trigger { display: flex; align-items: center; gap: .65rem; min-height: 44px; padding: .2rem .5rem .2rem .25rem; border: 1px solid transparent; border-radius: 99px; background: transparent; color: var(--text); font: inherit; text-align: start; cursor: pointer; }
	.trigger:hover, .trigger[aria-expanded='true'] { border-color: var(--line); background: var(--panel); }
	.avatar { display: grid; place-items: center; flex: none; width: 2.5rem; height: 2.5rem; border-radius: 50%; background: light-dark(#14213d, #0b1018); color: #fbbf24; font: 800 .9rem var(--body); }
	.who { display: grid; min-width: 0; max-width: 11rem; line-height: 1.2; }
	.who b, .who small { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.who small { color: var(--muted); font-size: .75rem; }
	.label { display: inline-flex; align-items: center; gap: .3rem; font: 800 .8rem var(--body); letter-spacing: .08em; text-transform: uppercase; }
	.panel { position: absolute; z-index: 20; inset: calc(100% + .4rem) 0 auto auto; display: grid; gap: .35rem; width: 17rem; padding: .85rem; border: 1px solid var(--line); border-radius: 16px; background: var(--panel); box-shadow: 0 12px 32px var(--card-shadow); }
	.role { text-transform: capitalize; color: var(--muted); font-size: .78rem; font-weight: 600; }
	hr { width: 100%; margin: .25rem 0; border: 0; border-top: 1px solid var(--line); }
	.row-item { display: flex; align-items: center; justify-content: space-between; min-height: 44px; padding: 0 .4rem; border: 0; border-radius: 8px; background: transparent; color: var(--text); font: 800 .95rem var(--body); text-decoration: none; cursor: pointer; }
	.row-item:hover { background: var(--panel-2); }
	.row-item:disabled { opacity: .5; cursor: wait; }
	.themes { display: grid; grid-template-columns: repeat(3, 1fr); gap: 2px; padding: 3px; border-radius: 10px; background: var(--panel-2); }
	.themes button { display: inline-flex; align-items: center; justify-content: center; gap: .3rem; min-height: 40px; padding: 0 .3rem; border: 0; border-radius: 8px; background: transparent; color: var(--text); font: 700 .8rem var(--body); cursor: pointer; }
	.themes button[aria-pressed='true'] { background: var(--accent-fill); color: var(--accent-ink); }
	.theme-button { display: grid; place-items: center; flex: none; width: 44px; height: 44px; border: 1px solid var(--line); border-radius: 50%; background: var(--panel); color: var(--text); font-size: 1.15rem; cursor: pointer; }
	.theme-button:hover { border-color: var(--accent); }
	@media (max-width: 960px) {
		.who, .label { display: none; }
		.account { position: static; }
		.panel { inset: 100% 0 auto 0; width: auto; border-radius: 0 0 16px 16px; border-width: 0 0 1px; }
	}
</style>
