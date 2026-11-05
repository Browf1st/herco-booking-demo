<script lang="ts">
	import { asset, resolve } from '$app/paths';
	import { page } from '$app/state';
	import { photos, shop } from '#lib/config.ts';

	const updates = [
		{ title: 'Encounter', category: 'Meetup', image: 'photos/encounter.png', summary: 'The poster lists October 17 at 7:00 PM at Pasyu Cafe, Valenzuela City.' },
		{ title: 'Online Tambike', category: 'Community', image: 'photos/online-tambike.png', summary: 'HERCO invited riders to share photos of their motorcycle builds.' },
		{ title: 'Find the Graphene Seal', category: 'Challenge', image: 'photos/graphene-seal.png', summary: 'A photo challenge to spot the Graphene Seal bottle among the detailing tools.' },
		{ title: 'Top Fan of the Week', category: 'Fan spotlight', image: 'photos/top-fan.png', summary: 'A weekly shoutout celebrating a member of the HERCO community.' }
	] as const;

	const pageSize = 5;
	const pageCount = Math.ceil(updates.length / pageSize);
	const requestedPage = $derived(Number(page.url.searchParams.get('page')));
	const currentPage = $derived(Number.isInteger(requestedPage) && requestedPage >= 1 && requestedPage <= pageCount ? requestedPage : 1);
	const visiblePosts = $derived(updates.slice((currentPage - 1) * pageSize, currentPage * pageSize));
</script>

<svelte:head><title>Announcements | HERCO Detailing Garage</title></svelte:head>

<section class="section">
	<div class="wrap stack announcement-feed">
		<p class="eyebrow">HERCO community</p>
		<h1>Announcements</h1>
		<p class="muted">Browse examples of HERCO’s meetups, community posts and challenges. Follow the shop on Facebook for current announcements.</p>
		<div class="stack posts">
			{#each visiblePosts as update (update.image)}
				<article class="post">
					<header class="post-author">
						<img class="avatar" src={asset(photos.logo)} alt="" width="46" height="46" />
						<div>
							<a class="author-name" href={shop.facebook} target="_blank" rel="noopener noreferrer">{shop.name}</a>
							<p class="small muted">{update.category}</p>
						</div>
					</header>
					<div class="post-caption">
						<h2>{update.title}</h2>
						<p>{update.summary}</p>
					</div>
					<a class="post-media" href={asset(update.image)} aria-label={`Open ${update.title} poster`}>
						<img src={asset(update.image)} alt="" width="1254" height="1254" loading="lazy" />
					</a>
				</article>
			{/each}
		</div>
		{#if pageCount > 1}
			<nav class="row pagination" aria-label="Announcement pages">
				{#each Array.from({ length: pageCount }, (_, i) => i + 1) as number (number)}
					<a
						href={resolve(number === 1 ? '/announcements' : `/announcements?page=${number}`)}
						aria-label={`Page ${number}`}
						aria-current={number === currentPage ? 'page' : undefined}
					>{number}</a>
				{/each}
			</nav>
		{/if}
		<div><a class="btn ghost" href={shop.facebook}>See current updates on Facebook</a></div>
	</div>
</section>

<style>
	.announcement-feed {
		max-width: 720px;
	}

	h1 {
		font-size: clamp(2.35rem, 8vw, 4.6rem);
	}

	.posts {
		gap: 24px;
	}

	.post {
		overflow: hidden;
		border: 1px solid var(--line);
		border-radius: 12px;
		background: var(--panel);
	}

	.post-author {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 16px 18px 0;
	}

	.avatar {
		border-radius: 50%;
		object-fit: cover;
	}

	.author-name {
		font-weight: 700;
		text-decoration: none;
	}

	.author-name:hover {
		text-decoration: underline;
	}

	.post-caption {
		display: grid;
		gap: 6px;
		padding: 14px 18px 18px;
	}

	.post-caption h2 {
		font: 700 1.125rem / 1.3 system-ui, sans-serif;
		text-transform: none;
	}

	.post-media,
	.post-media img {
		display: block;
		width: 100%;
		height: auto;
	}

	.pagination {
		justify-content: center;
	}

	.pagination a {
		display: grid;
		place-items: center;
		min-width: 44px;
		min-height: 44px;
		border: 1px solid var(--line);
		border-radius: 6px;
		text-decoration: none;
	}

	.pagination a[aria-current='page'] {
		background: var(--accent);
		color: var(--accent-ink);
	}
</style>
