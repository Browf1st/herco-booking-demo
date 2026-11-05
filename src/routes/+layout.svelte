<script lang="ts">
	import '../app.css';
	import { onMount } from 'svelte';
	import { resetDemoPointsOnRefresh, syncOperations } from '#lib/operations.svelte.ts';
	import { asset, resolve } from '$app/paths';
	import { page } from '$app/state';
	import { photos, shop } from '#lib/config.ts';
	import type { LayoutProps } from './$types';

	let { children }: LayoutProps = $props();
	const adminTabs = ['Overview', 'Bookings', 'Booking history', 'Customers', 'HERCO Points', 'Inventory', 'Reports & payments'];
	onMount(() => {
		resetDemoPointsOnRefresh();
		return syncOperations();
	});
</script>

<svelte:head>
	<title>{shop.name} | Book online</title>
</svelte:head>

<header>
	<div class="wrap row">
		<a class="logo" href={resolve('/')}>
			<img class="mark" src={asset(photos.logo)} alt="" />
			<span><b>Herco</b><small>Detailing Garage</small></span>
		</a>
		<nav class="row">
			{#if page.route.id === '/admin'}
				<a class="btn sm ghost" href={resolve('/')}>Back to user view</a>
			{:else}
			<a class="link wide" href={resolve('/#services')} aria-current={page.route.id === '/' && page.url.hash === '#services' ? 'location' : undefined}>Services</a>
			<a class="link" href={resolve('/announcements')} aria-current={page.route.id === '/announcements' ? 'page' : undefined}>Announcements</a>
			<a class="link wide" href={resolve('/preview')} aria-current={page.route.id === '/preview' ? 'page' : undefined}>Preview</a>
			<a class="link" href={resolve('/points')} aria-current={page.route.id === '/points' ? 'page' : undefined}>HercoPoints</a>
			<a class="btn sm" href={resolve('/book')} aria-current={page.route.id === '/book' ? 'page' : undefined}>Book</a>
			<a class="link admin-link" href={resolve('/admin')}>Admin view</a>
			{/if}
		</nav>
	</div>
	{#if page.route.id === '/admin'}
		<nav class="wrap admin-sections" aria-label="Admin sections">
			{#each adminTabs as tab}
				{@const requested = page.url.searchParams.get('tab') === 'Customers & points' ? 'HERCO Points' : page.url.searchParams.get('tab') ?? 'Overview'}
				{@const active = requested === tab}
				<a
					href={resolve(`/admin?tab=${encodeURIComponent(tab)}`)}
					aria-current={active ? 'page' : undefined}
				>{tab}</a>
			{/each}
		</nav>
	{/if}
</header>

<main>{@render children()}</main>

<footer>
	<div class="stripe"></div>
	<div class="wrap stack">
		<div class="row between">
			<div>
				<p class="display name">{shop.name}</p>
				<p class="muted small">{shop.area}. Open Wednesday to Sunday, 9AM to 5PM.</p>
			</div>
		</div>
	</div>
</footer>

<style>
	.admin-sections {
		display: flex;
		gap: 24px;
		overflow-x: auto;
		border-top: 1px solid var(--line);
	}

	.admin-sections a {
		flex-shrink: 0;
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
		font-size: 0.72rem;
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

	.between {
		justify-content: space-between;
	}

	.name {
		font-size: 1.5rem;
	}

	@media (max-width: 520px) {
		header .wrap {
			flex-wrap: wrap;
			gap: 8px;
			padding-block: 8px;
		}

		nav {
			flex-wrap: wrap;
		}
		header .link {
			font-size: 0.82rem;
			letter-spacing: 0.04em;
		}

		.wide {
			display: none;
		}

		.logo small {
			font-size: 0.6rem;
			letter-spacing: 0.14em;
		}
	}
</style>
