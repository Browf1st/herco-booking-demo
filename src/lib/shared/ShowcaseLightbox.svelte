<script lang="ts">
	import { untrack } from 'svelte';
	import { pushState } from '$app/navigation';
	import { asset, resolve } from '$app/paths';
	import { page } from '$app/state';
	import ActionIcon from './ActionIcon.svelte';
	import type { ShowcasePhoto } from './powder-showcase.ts';
	import { stepIndex, swipeDelta } from './showcase-gallery.ts';

	// `index` is -1 while closed. The parent sets it to open the viewer on that photo.
	let { photos, index = $bindable(-1) }: { photos: readonly ShowcasePhoto[]; index?: number } = $props();

	let dialog = $state<HTMLDialogElement>();
	let touch: { x: number; y: number } | undefined;
	const photo = $derived(index >= 0 ? photos[index] : undefined);
	const src = (slug: string, width: 480 | 960) => asset(`photos/showcase/${slug}-${width}.webp` as Parameters<typeof asset>[0]);

	$effect(() => {
		if (!dialog) return;
		if (photo && !dialog.open) {
			dialog.showModal();
			// A history entry lets the phone Back button close the viewer instead of leaving the page.
			if (!page.state.showcasePhoto) pushState('', { showcasePhoto: true });
		} else if (!photo && dialog.open) dialog.close();
	});

	// Back was pressed while the viewer was open.
	$effect(() => {
		if (!page.state.showcasePhoto && untrack(() => index) >= 0) index = -1;
	});

	function closed() {
		index = -1;
		if (page.state.showcasePhoto) history.back();
	}

	// Warm the cache for the neighbours so next/previous feels instant.
	$effect(() => {
		if (index < 0 || photos.length < 2) return;
		for (const delta of [1, -1]) new Image().src = src(photos[stepIndex(index, delta, photos.length)].slug, 960);
	});

	function go(delta: number) { index = stepIndex(index, delta, photos.length); }

	function keydown(event: KeyboardEvent) {
		if (event.key === 'ArrowRight') { event.preventDefault(); go(1); }
		else if (event.key === 'ArrowLeft') { event.preventDefault(); go(-1); }
	}

	function touchend(event: TouchEvent) {
		const end = event.changedTouches[0];
		if (!touch || !end) return;
		const delta = swipeDelta(end.clientX - touch.x, end.clientY - touch.y);
		touch = undefined;
		if (delta) go(delta);
	}
</script>

<dialog bind:this={dialog} class="lightbox" aria-labelledby="lightbox-title" onclose={closed} onkeydown={keydown}
	onclick={(event) => { if (event.target === dialog) dialog?.close(); }}>
	{#if photo}
		<div class="bar">
			<span class="counter" aria-live="polite">{index + 1} / {photos.length}</span>
			<button type="button" class="close-dialog" aria-label="Close photo viewer" onclick={() => dialog?.close()}><ActionIcon name="close" /></button>
		</div>
		<figure ontouchstart={(event) => {
			// Ignore pinch (two fingers) and moves while zoomed in, so zooming never changes the photo.
			const t = event.touches[0];
			touch = t && event.touches.length === 1 && (window.visualViewport?.scale ?? 1) <= 1 ? { x: t.clientX, y: t.clientY } : undefined;
		}} ontouchend={touchend}>
			{#key photo.slug}
				<img src={src(photo.slug, 960)} srcset={`${src(photo.slug, 480)} 480w, ${src(photo.slug, 960)} 960w`}
					sizes="(min-width: 1000px) 900px, 100vw" alt={photo.alt} width={photo.w} height={photo.h} decoding="async" />
			{/key}
			<figcaption>
				<h2 id="lightbox-title">{photo.title}</h2>
				{#if photo.finish}
					<a class="btn sm" href={resolve(`/book?service=wheel-colour&finish=${encodeURIComponent(photo.finish)}`)}><ActionIcon name="calendar" />Book this finish</a>
				{:else}
					<a class="btn sm ghost" href={resolve('/book?service=wheel-colour')}><ActionIcon name="calendar" />Book powder coating</a>
				{/if}
			</figcaption>
		</figure>
		{#if photos.length > 1}
			<button type="button" class="arrow prev" aria-label="Previous photo" onclick={() => go(-1)}><ActionIcon name="left" /></button>
			<button type="button" class="arrow next" aria-label="Next photo" onclick={() => go(1)}><ActionIcon name="right" /></button>
		{/if}
	{/if}
</dialog>

<style>
	.lightbox {
		width: min(100vw, 960px);
		max-width: 100vw;
		height: 100dvh;
		max-height: 100dvh;
		margin: auto;
		padding: 0;
		border: 0;
		background: #0b0b0c;
		color: #f4f4f5;
		overflow: hidden;
	}
	.lightbox[open] { display: grid; grid-template-rows: auto minmax(0, 1fr); }
	.lightbox::backdrop { background: #000d; }
	.bar { display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; }
	.counter { font-weight: 700; font-variant-numeric: tabular-nums; }
	.close-dialog {
		display: grid;
		place-items: center;
		width: 44px;
		height: 44px;
		border: 1px solid #fff5;
		border-radius: 50%;
		background: #0008;
		color: #fff;
		cursor: pointer;
	}
	.close-dialog:hover, .close-dialog:focus-visible { background: #fff2; }
	figure {
		display: grid;
		grid-template-rows: minmax(0, 1fr) auto;
		min-height: 0;
		margin: 0;
		touch-action: pan-y pinch-zoom;
	}
	img { width: 100%; height: 100%; min-height: 0; object-fit: contain; }
	figcaption { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 8px 12px; padding: 12px 16px 16px; }
	h2 { margin: 0; font-size: 1.15rem; line-height: 1.2; color: inherit; }
	.arrow {
		position: absolute;
		top: 50%;
		display: grid;
		place-items: center;
		width: 44px;
		height: 44px;
		border: 1px solid #fff5;
		border-radius: 50%;
		background: #000b;
		color: #fff;
		cursor: pointer;
		transform: translateY(-50%);
	}
	.arrow:hover, .arrow:focus-visible { background: #000e; }
	.prev { left: 8px; }
	.next { right: 8px; }
	@media (min-width: 1000px) {
		.lightbox { height: min(100dvh - 48px, 900px); border-radius: 8px; }
	}
</style>
