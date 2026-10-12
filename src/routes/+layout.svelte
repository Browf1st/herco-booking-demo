<script lang="ts">
	import '../app.css';
	import { shop, tiers, type Tier } from '#lib/config.ts';
	import { db, features, resetDemo, setTier } from '#lib/store.svelte.ts';
	import type { LayoutProps } from './$types';

	let { children }: LayoutProps = $props();
</script>

<svelte:head>
	<title>{shop.name} | Book online</title>
</svelte:head>

<header>
	<div class="wrap row">
		<a class="logo" href="/">
			<span class="mark">H</span>
			<span><b>Herco</b><small>Detailing Garage</small></span>
		</a>
		<nav class="row">
			<a class="link wide" href="/#services">Services</a>
			{#if features().preview}<a class="link" href="/preview">Preview</a>{/if}
			<a class="btn sm" href="/book">Book</a>
		</nav>
	</div>
</header>

<main>{@render children()}</main>

<footer>
	<div class="stripe"></div>
	<div class="wrap stack">
		<div class="row between">
			<div>
				<p class="display name">{shop.name}</p>
				<p class="muted small">{shop.area}. Open Wednesday to Sunday, 9AM to 5PM, strictly by schedule.</p>
			</div>
			<a class="link" href="/admin">Shop admin</a>
		</div>
		<div class="card demo row">
			<span class="small muted">Demo controls. Show the site as package:</span>
			{#each Object.entries(tiers) as [id, tier]}
				<button class="btn sm" class:ghost={db.tier !== id} onclick={() => setTier(id as Tier)}>{tier.label}</button>
			{/each}
			<button class="btn sm ghost" onclick={resetDemo}>Reset sample bookings</button>
		</div>
	</div>
</footer>

<style>
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
		display: grid;
		place-items: center;
		width: 38px;
		height: 38px;
		background: var(--accent);
		color: var(--accent-ink);
		font: italic 800 1.7rem var(--display);
		clip-path: polygon(10px 0, 100% 0, calc(100% - 10px) 100%, 0 100%);
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

	.demo {
		border-style: dashed;
	}

	@media (max-width: 520px) {
		.wide {
			display: none;
		}

		.logo small {
			font-size: 0.6rem;
			letter-spacing: 0.14em;
		}
	}
</style>
