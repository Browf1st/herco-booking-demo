<script lang="ts">
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { afterNavigate, goto } from '$app/navigation';
	import '../app.css';
	import { onMount } from 'svelte';
	import { syncBookings } from '#lib/demo/store.svelte.ts';
	import { saveFanProfile, syncOperations } from '#lib/demo/operations.svelte.ts';
	import { account } from '#lib/demo/account.svelte.ts';
	import { asset, resolve } from '$app/paths';
	import { page } from '$app/state';
	import { photos, shop } from '#lib/shared/config.ts';
	import type { LayoutProps } from './$types';
	import { adminNavigation, adminPath } from '#lib/demo/adminNavigation.ts';
	import { switchStaffSession, syncStaffAccess } from '#lib/demo/staffAccess.svelte.ts';
	import { parseWorkspaceAccess, workspaceLanding, workspaceGroups, workspaceLinks, type WorkspaceAccess } from '#lib/shared/workspace-navigation.ts';
	import { THEME_EVENT } from '#lib/shared/theme.ts';

	let { children }: LayoutProps = $props();
	let bookMenu = $state<HTMLDetailsElement>();
	let menuOpen = $state(false);
	let menuTrigger: HTMLButtonElement;
	let header: HTMLElement;
	let accountMenu = $state<HTMLDetailsElement>();
	let workerAccess = $state<WorkspaceAccess | null>(null);
	let workerNavigation = $state<'loading' | 'ready' | 'error'>('loading');
	let signingOut = $state(false);
	let navigationError = $state('');
	let pendingCounts = $state<{ bookings: number; requests: number }>();
	let accessRequest = 0;
	const workerGroups = $derived(workerAccess ? workspaceGroups(workerAccess) : []);
	const openOwnerMenu = () => header?.querySelector<HTMLDetailsElement>('.owner-group[open]');
	afterNavigate(() => {
		menuOpen = false;
		if (bookMenu) bookMenu.open = false;
		const open = openOwnerMenu();
		if (open) open.open = false;
		if (accountMenu) accountMenu.open = false;
		if (!demo) void refreshWorkerNavigation();
	});
	let theme = $state<'system' | 'light' | 'dark'>('system');
	let themeMenu: HTMLDetailsElement;
	let themeTrigger: HTMLElement;
	const themes = [{ value: 'system', label: 'System' }, { value: 'light', label: 'Light' }, { value: 'dark', label: 'Dark' }] as const;
	const activeAdmin = $derived(adminNavigation(page.url.searchParams));
	const ownerLinks = [{ tab: 'Reports', label: 'Reports' }, { tab: 'Staff Access', label: 'Accounts' }, { tab: 'Activity log', label: 'Activity Log' }] as const;
	const moreTabs = ['Booking', 'Customers', 'HERCO Points', 'Inventory', 'Pricing'] as const;
	const demo = import.meta.env.MODE !== 'worker';
	let sessionError = $state('');
	const customerOnlyRoutes = new Set(['/', '/book', '/points', '/my-bookings', '/preview', '/walk-in']);
	const staffOnlyRoutes = new Set(['/admin', '/booking-history', '/reports', '/customers', '/staff-points', '/inventory',
		'/pricing', '/activity-log', '/staff-access', '/manual-booking', '/complete-booking', '/booking-services', '/booking-prices']);

	function staffLinkIsCurrent(href: string) {
		const [pathname, query] = href.split('?');
		if (page.url.pathname !== resolve(pathname as '/admin')) return false;
		const params = new URLSearchParams(query ?? '');
		if (pathname === '/manual-booking') return page.url.searchParams.has('walk-in') === params.has('walk-in');
		return query ? page.url.searchParams.get('view') === params.get('view') :
			pathname !== '/admin' || page.url.searchParams.get('view') !== 'requests';
	}

	const linkIcons: Record<string, 'calendar' | 'edit' | 'history' | 'add'> = {
		'/admin': 'calendar', '/admin?view=requests': 'edit', '/booking-history': 'history',
		'/manual-booking': 'add', '/manual-booking?walk-in=1': 'add'
	};
	function linkCount(href: string) {
		if (!pendingCounts) return undefined;
		return href === '/admin' ? pendingCounts.bookings : href === '/admin?view=requests' ? pendingCounts.requests : undefined;
	}

	async function refreshPendingCounts(access: WorkspaceAccess) {
		if (!access.pages.includes('Bookings')) { pendingCounts = undefined; return; }
		try {
			const response = await fetch(resolve('/api/staff/counts'), { headers: { accept: 'application/json' } });
			if (!response.ok) throw new Error();
			const counts = await response.json();
			pendingCounts = { bookings: Number(counts?.bookings) || 0, requests: Number(counts?.requests) || 0 };
		} catch { pendingCounts = undefined; }
	}

	async function refreshWorkerNavigation() {
		const request = ++accessRequest;
		try {
			const response = await fetch(resolve('/api/staff/workspace'), { headers: { accept: 'application/json' } });
			if (request !== accessRequest) return;
			if (response.status === 401 || response.status === 403) {
				workerAccess = null;
				pendingCounts = undefined;
				workerNavigation = 'ready';
				// Staff pages need a staff account: send visitors to sign in and customers to their bookings.
				if (staffOnlyRoutes.has(page.url.pathname)) {
					await goto(resolve(response.status === 401 ? '/account' : '/my-bookings'), { replaceState: true });
				}
				return;
			}
			if (!response.ok) throw new Error();
			const access = parseWorkspaceAccess(await response.json());
			if (request !== accessRequest) return;
			if (!access) throw new Error();
			workerAccess = access;
			workerNavigation = 'ready';
			void refreshPendingCounts(access);
			const permitted = new Set(workspaceLinks(access).map(link => link.href.split('?')[0]));
			if (permitted.has('/admin')) for (const task of ['/complete-booking', '/booking-services', '/booking-prices']) permitted.add(task);
			if (customerOnlyRoutes.has(page.url.pathname) || (staffOnlyRoutes.has(page.url.pathname) && !permitted.has(page.url.pathname))) {
				await goto(resolve(workspaceLanding(access) as '/admin'), { replaceState: true });
			}
		} catch {
			if (request !== accessRequest) return;
			workerAccess = null;
			workerNavigation = 'error';
		}
	}

	async function signOutWorker() {
		if (signingOut) return;
		signingOut = true;
		navigationError = '';
		try {
			const response = await fetch(resolve('/api/auth/session'), { method: 'DELETE', headers: { accept: 'application/json' } });
			if (!response.ok) throw new Error();
			accessRequest++;
			workerAccess = null;
			pendingCounts = undefined;
			workerNavigation = 'ready';
			if (accountMenu) accountMenu.open = false;
			await goto(resolve('/account'), { invalidateAll: true });
			window.dispatchEvent(new Event('herco-account-changed'));
		} catch {
			navigationError = 'Could not sign out. Try again.';
		} finally { signingOut = false; }
	}

	function selectDemoView(event: MouseEvent, view: 'admin' | 'owner') {
		if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
		sessionError = '';
		try {
			switchStaffSession(view);
		} catch (error) {
			event.preventDefault();
			sessionError = error instanceof Error ? error.message : 'Could not change the demo session.';
		}
	}

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
		window.dispatchEvent(new Event(THEME_EVENT));
		themeMenu.open = false;
		themeTrigger.focus();
	}

	onMount(() => {
		syncTheme();
		const onThemeStorage = (event: StorageEvent) => {
			if (event.key === 'herco-theme' || event.key === null) applyTheme(event.newValue ?? 'system');
		};
		window.addEventListener('storage', onThemeStorage);
		window.addEventListener(THEME_EVENT, syncTheme);
		if (!demo) {
			const refresh = () => { void refreshWorkerNavigation(); };
			window.addEventListener('herco-account-changed', refresh);
			window.addEventListener('focus', refresh);
			return () => {
				window.removeEventListener('storage', onThemeStorage);
				window.removeEventListener(THEME_EVENT, syncTheme);
				window.removeEventListener('herco-account-changed', refresh);
				window.removeEventListener('focus', refresh);
			};
		}
		const stopOperations = syncOperations();
		if (account.current) saveFanProfile(account.current);
		const stopBookings = syncBookings();
		const stopStaffAccess = syncStaffAccess();
		return () => {
			window.removeEventListener('storage', onThemeStorage);
			window.removeEventListener(THEME_EVENT, syncTheme);
			stopOperations();
			stopBookings();
			stopStaffAccess();
		};
	});
</script>

<svelte:head>
	<title>{shop.name} | Book online</title>
</svelte:head>

<svelte:window onclick={(event) => {
	const open = openOwnerMenu();
	if (open && event.target instanceof Node && !open.contains(event.target)) open.open = false;
	if (themeMenu?.open && event.target instanceof Node && !themeMenu.contains(event.target)) themeMenu.open = false;
	if (bookMenu?.open && event.target instanceof Node && !bookMenu.contains(event.target)) bookMenu.open = false;
	if (accountMenu?.open && event.target instanceof Node && !accountMenu.contains(event.target)) accountMenu.open = false;
	if (menuOpen && event.target instanceof Node && !header.contains(event.target)) menuOpen = false;
}} onkeydown={(event) => {
	if (event.key === 'Escape' && accountMenu?.open) {
		accountMenu.open = false;
		accountMenu.querySelector('summary')?.focus();
	} else if (event.key === 'Escape' && themeMenu?.open) {
		themeMenu.open = false;
		themeTrigger.focus();
	} else if (event.key === 'Escape' && bookMenu?.open) {
		bookMenu.open = false;
		bookMenu.querySelector('summary')?.focus();
	} else if (event.key === 'Escape' && openOwnerMenu()) {
		const open = openOwnerMenu()!;
		open.open = false;
		open.querySelector('summary')?.focus();
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
		{#if demo}<nav class="view-switch" aria-label="Demo views">
			<a href={resolve('/')} aria-current={page.route.id !== '/admin' ? 'true' : undefined}>User view</a>
			<a href={resolve('/admin')} aria-current={page.route.id === '/admin' && !activeAdmin.owner ? 'true' : undefined} onclick={(event) => selectDemoView(event, 'admin')}>Admin view</a>
			<a href={resolve(adminPath('Booking'))} aria-current={page.route.id === '/admin' && activeAdmin.owner ? 'true' : undefined} onclick={(event) => selectDemoView(event, 'owner')}>Owner view</a>
		</nav>{/if}
	</div>
	{#if sessionError}<p class="wrap error small" role="alert">{sessionError}</p>{/if}
</div>

<header bind:this={header}>
	<div class="wrap row" class:admin-header={demo ? page.route.id === '/admin' : Boolean(workerAccess)} class:owner-header={demo ? page.route.id === '/admin' && activeAdmin.owner : workerAccess?.role === 'owner' || workerAccess?.role === 'superadmin'}>
		<a class="logo" href={!demo && workerAccess ? resolve(workspaceLanding(workerAccess) as '/admin') : resolve('/')}>
			<img class="mark" src={asset(photos.logo)} alt="" />
			<span><b>Herco</b><small>Detailing Garage</small></span>
		</a>
		<button class="menu-trigger" type="button" bind:this={menuTrigger} aria-expanded={menuOpen} aria-controls="header-navigation" aria-label={menuOpen ? 'Close navigation' : 'Open navigation'} onclick={() => menuOpen = !menuOpen}>
			<ActionIcon name={menuOpen ? 'close' : 'menu'} />
		</button>
		{#if !demo && (workerAccess || workerNavigation === 'error' || (workerNavigation === 'loading' && !customerOnlyRoutes.has(page.url.pathname)))}
		<nav id="header-navigation" class="admin-sections main-nav staff-main-nav" class:owner-sections={workerAccess?.role === 'owner' || workerAccess?.role === 'superadmin'} class:menu-open={menuOpen} aria-label="Staff navigation">
			{#if workerNavigation === 'error'}
				<button class="navigation-retry" type="button" onclick={() => refreshWorkerNavigation()}><ActionIcon name="reset" />Retry navigation</button>
			{:else if workerAccess}
				{#each workerGroups as group (group.label)}
					{#if group.links.length === 1 && group.label !== 'More' && group.label !== 'Booking'}
						<a href={resolve(group.links[0].href as '/admin')} aria-current={staffLinkIsCurrent(group.links[0].href) ? 'page' : undefined}>{group.label}</a>
					{:else}
						<details class="owner-group" class:group-current={group.links.some(link => staffLinkIsCurrent(link.href))}>
							<summary>{group.label}{#if group.label === 'Booking' && pendingCounts && pendingCounts.bookings + pendingCounts.requests > 0}<span class="tab-count" aria-label={(pendingCounts.bookings + pendingCounts.requests) + ' awaiting action'}>{pendingCounts.bookings + pendingCounts.requests}</span>{/if} <span class="owner-caret" aria-hidden="true"></span></summary>
							<div class="owner-options">{#each group.links as link (link.href)}
								{@const count = linkCount(link.href)}
								<a href={resolve(link.href as '/admin')} aria-current={staffLinkIsCurrent(link.href) ? 'page' : undefined}>{#if linkIcons[link.href]}<ActionIcon name={linkIcons[link.href]} />{/if}<span class="option-label">{link.label}</span>{#if count !== undefined}<span class="tab-count" aria-label={count + (link.href === '/admin' ? ' pending bookings' : ' awaiting review')}>{count}</span>{/if}</a>
							{/each}</div>
						</details>
					{/if}
				{/each}
			{/if}
			<details class="account-menu" bind:this={accountMenu}>
				<summary><ActionIcon name="user" />Account <span class="owner-caret" aria-hidden="true"></span></summary>
				<div class="account-options">
					{#if workerAccess}<span class="muted small">{workerAccess.role === 'owner' ? 'Owner' : workerAccess.role === 'superadmin' ? 'Superadmin' : workerAccess.role === 'staff' ? 'Staff' : 'Admin'}</span>{/if}
					<a href={resolve('/account')}>Account settings</a>
					{#if workerAccess}<button type="button" onclick={signOutWorker} disabled={signingOut}>{signingOut ? 'Signing out…' : 'Sign out'}</button>{/if}
				</div>
			</details>
		</nav>
		{:else if !demo || page.route.id !== '/admin'}
		<nav id="header-navigation" class="row main-nav" class:menu-open={menuOpen} aria-label="Customer navigation">
			<a class="link" href={resolve('/#services')} aria-current={page.route.id === '/' && page.url.hash === '#services' ? 'location' : undefined}>Services</a>
			<a class="link" href={resolve('/preview')} aria-current={page.route.id === '/preview' ? 'page' : undefined}>Showcase</a>
			<a class="link" href={resolve('/points')} aria-current={page.route.id === '/points' ? 'page' : undefined}>HERCO Points</a>
			<a class="link" href={resolve('/my-bookings')} aria-current={page.route.id === '/my-bookings' ? 'page' : undefined}>Bookings</a>
			<a class="link" href={resolve('/account')} aria-current={page.route.id === '/account' ? 'page' : undefined}>Account</a>
			<details class="book-menu" bind:this={bookMenu}>
				<summary class="btn sm" class:booking-current={page.route.id === '/book'}><ActionIcon name="calendar" />Book <span aria-hidden="true">▾</span></summary>
				<div class="book-options">
					<a href={resolve('/book')} data-sveltekit-reload aria-current={page.route.id === '/book' && !page.url.searchParams.has('walk-in') ? 'page' : undefined}>Online</a>
					<a href={demo ? resolve('/book?walk-in=1') : resolve('/walk-in')} data-sveltekit-reload aria-current={(demo ? page.route.id === '/book' && page.url.searchParams.has('walk-in') : page.route.id === '/walk-in') ? 'page' : undefined}>Walk-in</a>
				</div>
			</details>
		</nav>
		{:else}
		<nav id="header-navigation" class="admin-sections main-nav" class:owner-sections={activeAdmin.owner} class:menu-open={menuOpen} aria-label="Admin sections">
			{#if activeAdmin.owner}
				{#each ownerLinks as { tab, label } (tab)}
					<a href={resolve(adminPath(tab))} aria-current={activeAdmin.allowed && activeAdmin.tab === tab ? 'page' : undefined}>{label}</a>
				{/each}
				<details class="owner-group" class:group-current={activeAdmin.allowed && moreTabs.some(tab => tab === activeAdmin.tab)}>
					<summary>More <span class="owner-caret" aria-hidden="true"></span></summary>
					<div class="owner-options">
						{#each moreTabs as tab (tab)}
							<a href={resolve(adminPath(tab))} aria-current={activeAdmin.allowed && activeAdmin.tab === tab ? 'page' : undefined}>{tab}</a>
						{/each}
					</div>
				</details>
			{:else}
			{#each activeAdmin.tabs as tab (tab)}
				<a
					href={resolve(adminPath(tab))}
					aria-current={activeAdmin.allowed && activeAdmin.tab === tab ? 'page' : undefined}
				>{tab}</a>
			{/each}
			{/if}
		</nav>
		{/if}
	</div>
</header>
	{#if navigationError}<p class="wrap error small" role="alert">{navigationError}</p>{/if}

<main>{@render children()}</main>

<footer>
	<div class="stripe"></div>
	<div class="wrap stack">
		<div class="row">
			<img class="mark" src={asset(photos.logo)} alt="" width="54" height="46" />
			<div>
				<p class="display name">{shop.name}</p>
				<p class="muted small">{shop.area}. Open Wednesday to Sunday, 9AM to 5PM.</p>
				{#if !demo}<a class="small" href={resolve('/privacy-preferences')}>Privacy preferences</a>{/if}
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

	.admin-sections.owner-sections { overflow: visible; flex-wrap: wrap; gap: 0 clamp(.75rem, 2vw, 1.5rem); }
	.owner-header { max-width: 1420px; }
	.owner-group { position: relative; }
	.owner-group summary {
		display: flex;
		align-items: center;
		gap: .45rem;
		list-style: none;
		padding: 12px .2rem 12px 0;
		border-bottom: 3px solid transparent;
		font: 700 1.05rem var(--display);
		letter-spacing: .05em;
		text-transform: uppercase;
		cursor: pointer;
	}
	.owner-group summary::-webkit-details-marker { display: none; }
	@media (min-width: 961px) {
		.owner-group > summary { height: 100%; }
	}
	.owner-group.group-current > summary { color: var(--accent); border-bottom-color: var(--accent); }
	.owner-caret { width: .42rem; height: .42rem; border: solid currentColor; border-width: 0 1.5px 1.5px 0; rotate: 45deg; }
	.owner-group[open] > summary .owner-caret { rotate: 225deg; }
	.owner-options {
		position: absolute;
		inset: 100% 0 auto auto;
		z-index: 1;
		min-width: 11rem;
		padding: .25rem;
		background: var(--panel);
		border: 1px solid var(--line);
		border-radius: 6px;
		box-shadow: 0 4px 12px var(--card-shadow);
	}
	.owner-options a { padding: .5rem .65rem; border: 0; border-radius: 4px; font: 650 .92rem var(--body); letter-spacing: 0; text-transform: none; }
	.owner-options a:hover, .owner-options a[aria-current='page'] { background: var(--panel-2); }

	.book-menu { position: relative; }
	.book-menu summary { list-style: none; }
	.book-menu summary::-webkit-details-marker { display: none; }
	.book-options { position: absolute; inset: calc(100% + .3rem) 0 auto auto; min-width: 9rem; padding: .25rem; background: var(--panel); border: 1px solid var(--line); border-radius: 6px; box-shadow: 0 4px 12px var(--card-shadow); z-index: 2; }
	.book-options a { display: block; padding: .55rem .7rem; border-radius: 4px; text-decoration: none; }
	.book-options a:hover { background: var(--panel-2); }
	@media (max-width: 800px) { .book-options { position: static; margin-top: .25rem; } }
	.menu-trigger { display: none; }
	/* Staff header reuses the demo admin tabs; dropdowns need visible overflow to open below the bar. */
	.staff-main-nav { overflow: visible; flex-wrap: wrap; justify-content: flex-end; gap: 0 clamp(.75rem, 2vw, 1.5rem); }
	.owner-options a { display: flex; align-items: center; gap: .5rem; white-space: nowrap; }
	.owner-options .option-label { flex: 1; }
	.owner-group summary .tab-count { margin-inline-start: .1rem; }
	.account-menu { position: relative; }
	.account-menu summary { display: flex; align-items: center; gap: .45rem; height: 100%; cursor: pointer; list-style: none; padding: 12px 0; border-bottom: 3px solid transparent; font: 700 1.05rem var(--display); letter-spacing: .05em; text-transform: uppercase; }
	.account-menu summary::-webkit-details-marker { display: none; }
	.account-menu[open] > summary .owner-caret { rotate: 225deg; }
	.account-options { position: absolute; inset: 100% 0 auto auto; z-index: 1; display: grid; gap: .15rem; min-width: 11rem; padding: .25rem; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); box-shadow: 0 4px 12px var(--card-shadow); }
	.account-options .muted { padding: .35rem .65rem 0; }
	.account-options a, .account-options button { padding: .5rem .65rem; border: 0; border-radius: 4px; background: transparent; color: var(--text); font: 650 .92rem var(--body); letter-spacing: 0; text-transform: none; text-align: start; text-decoration: none; cursor: pointer; }
	.account-options a:hover, .account-options button:hover { background: var(--panel-2); }
	.navigation-retry { display: flex; align-items: center; gap: .4rem; border: 0; background: transparent; color: var(--text); font: 700 1.05rem var(--display); text-transform: uppercase; cursor: pointer; }

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

	.booking-current {
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
		.staff-main-nav.menu-open { justify-content: stretch; }
		.admin-sections.owner-sections { overflow: auto; }
		.owner-group summary { padding: .5rem; }
		.owner-options { position: static; min-width: 0; box-shadow: none; }
		.main-nav a { padding: .5rem; }
		.main-nav a[aria-current] { color: var(--accent); }
		.account-options { position: static; box-shadow: none; }
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
