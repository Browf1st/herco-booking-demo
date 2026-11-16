<script lang="ts">
	import ActionIcon from '#lib/ActionIcon.svelte';
	import { afterNavigate } from '$app/navigation';
	import '../app.css';
	import { onMount } from 'svelte';
	import { syncBookings } from '#lib/store.svelte.ts';
	import { saveFanProfile, syncOperations } from '#lib/operations.svelte.ts';
	import { account } from '#lib/account.svelte.ts';
	import { asset, resolve } from '$app/paths';
	import { page } from '$app/state';
	import { photos, shop } from '#lib/config.ts';
	import type { LayoutProps } from './$types';
	import { adminNavigation, adminPath, adminTabs } from '#lib/adminNavigation.ts';

	let { children }: LayoutProps = $props();
	let menuOpen = $state(false);
	let menuTrigger: HTMLButtonElement;
	let header: HTMLElement;
	afterNavigate(() => { menuOpen = false; });
	let theme = $state<'system' | 'light' | 'dark'>('system');
	let themeMenu: HTMLDetailsElement;
	let themeTrigger: HTMLElement;
	const themes = [{ value: 'system', label: 'System' }, { value: 'light', label: 'Light' }, { value: 'dark', label: 'Dark' }] as const;
	const activeAdmin = $derived(adminNavigation(page.url.searchParams));

	function syncTheme() {
		const current = document.documentElement.dataset.theme;
		theme = current === 'light' || current === 'dark' ? current : 'system';
	}

	function applyTheme(value: string) {
		if (value === 'light' || value === 'dark') document.documentElement.dataset.theme = value;
		else delete document.documentElement.dataset.theme;
		syncTheme();
	}

	function chooseTheme(value: typeof theme) {
		applyTheme(value);
		try {
			if (theme === 'system') localStorage.removeItem('herco-theme');
			else localStorage.setItem('herco-theme', theme);
		} catch {}
		themeMenu.open = false;
		themeTrigger.focus();
	}

	onMount(() => {
		syncTheme();
		const onThemeStorage = (event: StorageEvent) => {
			if (event.key === 'herco-theme' || event.key === null) applyTheme(event.newValue ?? 'system');
		};
		window.addEventListener('storage', onThemeStorage);
		const stopOperations = syncOperations();
		if (account.current) saveFanProfile(account.current);
		const stopBookings = syncBookings();
		return () => {
			window.removeEventListener('storage', onThemeStorage);
			stopOperations();
			stopBookings();
		};
	});
</script>

<svelte:head>
	<title>{shop.name} | Book online</title>
</svelte:head>

<svelte:window onclick={(event) => {
	if (themeMenu?.open && event.target instanceof Node && !themeMenu.contains(event.target)) themeMenu.open = false;
	if (menuOpen && event.target instanceof Node && !header.contains(event.target)) menuOpen = false;
}} onkeydown={(event) => {
	if (event.key === 'Escape' && themeMenu?.open) {
		themeMenu.open = false;
		themeTrigger.focus();
	} else if (event.key === 'Escape' && menuOpen) {
		menuOpen = false;
		menuTrigger.focus();
	}
}} />

<div class="demo-switch">
	<div class="wrap">
		<details class="theme-picker" bind:this={themeMenu}>
			<summary bind:this={themeTrigger} aria-label={'Appearance: ' + theme} title={'Appearance: ' + theme}>
				<ActionIcon name={theme === 'system' ? 'system' : theme === 'light' ? 'sun' : 'moon'} />
			</summary>
			<div class="theme-options" role="group" aria-label="Appearance choices">
				{#each themes as option (option.value)}
					<button type="button" aria-pressed={theme === option.value} onclick={() => chooseTheme(option.value)}><ActionIcon name={option.value === "system" ? "system" : option.value === "light" ? "sun" : "moon"} />
						<span class="theme-label">{option.label}</span>
						{#if theme === option.value}<span class="theme-check" aria-hidden="true">✓</span>{/if}
					</button>
				{/each}
			</div>
		</details>
		<nav class="view-switch" aria-label="Demo views">
			<a href={resolve('/')} aria-current={page.route.id !== '/admin' ? 'true' : undefined}>User view</a>
			<a href={resolve('/admin')} aria-current={page.route.id === '/admin' && !activeAdmin.owner ? 'true' : undefined}>Admin view</a>
			<a href={resolve(adminPath('Booking', true))} aria-current={page.route.id === '/admin' && activeAdmin.owner ? 'true' : undefined}>Owner view</a>
		</nav>
	</div>
</div>

<header bind:this={header}>
	<div class="wrap row" class:admin-header={page.route.id === '/admin'}>
		<a class="logo" href={resolve('/')}>
			<img class="mark" src={asset(photos.logo)} alt="" />
			<span><b>Herco</b><small>Detailing Garage</small></span>
		</a>
		<button class="menu-trigger" type="button" bind:this={menuTrigger} aria-expanded={menuOpen} aria-controls="header-navigation" aria-label={menuOpen ? 'Close navigation' : 'Open navigation'} onclick={() => menuOpen = !menuOpen}>
			<ActionIcon name={menuOpen ? 'close' : 'menu'} />
		</button>
		{#if page.route.id !== '/admin'}
		<nav id="header-navigation" class="row main-nav" class:menu-open={menuOpen} aria-label="Customer navigation">
			<a class="link" href={resolve('/#services')} aria-current={page.route.id === '/' && page.url.hash === '#services' ? 'location' : undefined}>Services</a>
			<a class="link" href={resolve('/preview')} aria-current={page.route.id === '/preview' ? 'page' : undefined}>Showcase</a>
			<a class="link" href={resolve('/points')} aria-current={page.route.id === '/points' ? 'page' : undefined}>HERCO Points</a>
			<a class="link" href={resolve('/account')} aria-current={['/account', '/my-bookings'].includes(page.route.id ?? '') ? 'page' : undefined}>Account</a>
			<a class="btn sm" href={resolve('/book')} aria-current={page.route.id === '/book' ? 'page' : undefined}><ActionIcon name="calendar" />Book</a>
		</nav>
		{:else}
		<nav id="header-navigation" class="admin-sections main-nav" class:menu-open={menuOpen} aria-label="Admin sections">
			{#each adminTabs.filter(tab => activeAdmin.owner || tab !== 'Activity log') as tab}
				<a
					href={resolve(adminPath(tab, activeAdmin.owner))}
					aria-current={activeAdmin.tab === tab ? 'page' : undefined}
				>{tab}</a>
			{/each}
		</nav>
		{/if}
	</div>
</header>

<main>{@render children()}</main>

<footer>
	<div class="stripe"></div>
	<div class="wrap stack">
		<div class="row">
			<img class="mark" src={asset(photos.logo)} alt="" width="54" height="46" />
			<div>
				<p class="display name">{shop.name}</p>
				<p class="muted small">{shop.area}. Open Wednesday to Sunday, 9AM to 5PM.</p>
			</div>
		</div>
	</div>
</footer>

<style>
	.demo-switch {
		position: relative;
		z-index: 11;
		border-bottom: 1px solid var(--line);
		background: var(--panel-2);
	}

	.demo-switch .wrap {
		display: flex;
		justify-content: flex-end;
		align-items: center;
		flex-wrap: wrap;
		gap: .25rem .9rem;
		padding-block: .2rem;
	}

	.theme-picker { position: relative; }
	.theme-picker summary { display: grid; place-items: center; width: 2.15rem; height: 2.15rem; list-style: none; border: 1px solid var(--line); border-radius: .35rem; background: var(--panel); cursor: pointer; }
	.theme-picker summary::-webkit-details-marker { display: none; }
	.theme-picker summary:hover, .theme-picker[open] summary { color: var(--accent); }
	.theme-options { position: absolute; inset-inline-end: 0; top: calc(100% + .35rem); display: grid; gap: .15rem; min-width: 7.5rem; padding: .25rem; background: var(--panel); border: 1px solid var(--line); border-radius: .4rem; box-shadow: 0 4px 12px var(--card-shadow); }
	.theme-options button { display: grid; grid-template-columns: 1em minmax(0, 1fr) 1em; align-items: center; gap: .5rem; padding: .35rem .55rem; border: 0; border-radius: .2rem; background: transparent; color: var(--text); font: inherit; font-size: .85rem; text-align: start; cursor: pointer; }
	.theme-options button:hover, .theme-options button[aria-pressed='true'] { background: var(--panel-2); }
	.theme-check { color: var(--accent); text-align: center; }

	.view-switch { display: inline-flex; align-items: center; gap: 2px; padding: 2px; border: 1px solid var(--line); border-radius: .45rem; background: var(--panel); }
	.view-switch a { padding: .3rem .55rem; border-radius: .29rem; color: var(--muted); font-size: .77rem; font-weight: 700; text-decoration: none; white-space: nowrap; }
	.view-switch a:hover:not([aria-current]) { background: var(--panel-2); color: var(--text); }
	.view-switch a[aria-current] { background: var(--accent-fill); color: var(--accent-ink); }
	.view-switch a:focus-visible { outline-offset: -2px; outline-color: currentColor; }


	.admin-sections {
		display: flex;
		align-self: stretch;
		align-items: stretch;
		gap: clamp(.75rem, 2vw, 1.5rem);
		min-width: 0;
		overflow-x: auto;
	}

	.admin-header .logo { flex-shrink: 0; }

	.admin-sections a {
		flex-shrink: 0;
		display: flex;
		align-items: center;
		white-space: nowrap;
		padding-block: 12px;
		border-bottom: 3px solid transparent;
		text-decoration: none;
		font: 700 1.05rem var(--display);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.admin-sections a[aria-current='page'] {
		color: var(--accent);
		border-bottom-color: var(--accent);
	}

	.menu-trigger { display: none; }

	header {
		position: sticky;
		top: 0;
		z-index: 10;
		background: color-mix(in srgb, var(--bg) 88%, transparent);
		backdrop-filter: blur(10px);
		border-bottom: 1px solid var(--line);
	}

	header .wrap,
	nav {
		flex-wrap: nowrap;
	}

	header .wrap {
		justify-content: space-between;
		min-height: 60px;
	}

	.logo {
		display: flex;
		align-items: center;
		gap: 10px;
		text-decoration: none;
		font-family: var(--display);
		text-transform: uppercase;
		line-height: 1;
	}

	.mark {
		width: 54px;
		height: 46px;
		object-fit: contain;
	}

	.logo b {
		display: block;
		font: italic 800 1.5rem var(--display);
		letter-spacing: 0.04em;
	}

	.logo small {
		color: var(--muted);
		font-size: 0.8rem;
		font-weight: 600;
		letter-spacing: 0.22em;
	}

	.link {
		font: 700 1.05rem var(--display);
		letter-spacing: 0.1em;
		text-decoration: none;
		text-transform: uppercase;
	}

	.link:hover {
		color: var(--accent);
	}

	.link[aria-current] {
		color: var(--accent);
		text-decoration: underline;
		text-underline-offset: 8px;
		text-decoration-thickness: 3px;
	}

	.btn[aria-current] {
		box-shadow: inset 0 -4px 0 var(--text);
	}

	main {
		min-height: 70vh;
	}

	footer .wrap {
		padding-top: 28px;
		padding-bottom: 28px;
	}

	.name {
		font-size: 1.5rem;
	}

	@media (max-width: 960px) {
		header .wrap {
			gap: 8px;
			padding-block: 8px;
		}

		header .menu-trigger { display: grid; place-items: center; width: 44px; height: 44px; flex: none; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); color: var(--text); font-size: 1.35rem; cursor: pointer; }
		.main-nav {
			display: none;
			position: absolute;
			top: 100%;
			inset-inline: 0;
			padding: .5rem 16px;
			background: var(--panel);
			border-bottom: 1px solid var(--line);
			box-shadow: 0 5px 12px var(--card-shadow);
			max-height: 65dvh;
			overflow-y: auto;
		}
		.main-nav.menu-open { display: grid; gap: .25rem; }
		.main-nav a { padding: .5rem; }
		.main-nav a[aria-current] { color: var(--accent); }
		.main-nav .btn[aria-current] { color: var(--accent-ink); }
		header .link {
			font-size: 0.95rem;
			letter-spacing: 0.04em;
		}

		.logo small {
			font-size: 0.75rem;
			letter-spacing: 0.14em;
		}
	}
</style>
