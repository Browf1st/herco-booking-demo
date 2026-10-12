<script lang="ts">
	let { before, after, alt }: { before: string; after: string; alt: string } = $props();

	let pos = $state(50);
</script>

<!-- A full-size invisible range input gives drag, touch and keyboard control without custom pointer code. -->
<div class="compare" style:--pos="{pos}%">
	<img src={after} alt="{alt}, after" />
	<img class="before" src={before} alt="{alt}, before" />
	<span class="tag">Before</span>
	<span class="tag after">After</span>
	<span class="handle"></span>
	<input type="range" min="0" max="100" bind:value={pos} aria-label="Drag to compare before and after" />
</div>

<style>
	.compare {
		position: relative;
		aspect-ratio: 8 / 5;
		overflow: hidden;
		border: 1px solid var(--line);
		border-radius: 6px;
	}

	img,
	input {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
	}

	img {
		object-fit: cover;
	}

	.before {
		clip-path: inset(0 calc(100% - var(--pos)) 0 0);
	}

	.tag {
		position: absolute;
		top: 10px;
		left: 10px;
		padding: 2px 10px;
		background: var(--bg);
		font: 700 0.9rem var(--display);
		letter-spacing: 0.12em;
		text-transform: uppercase;
	}

	.after {
		left: auto;
		right: 10px;
		background: var(--accent);
		color: var(--accent-ink);
	}

	.handle {
		position: absolute;
		top: 0;
		bottom: 0;
		left: var(--pos);
		width: 3px;
		background: var(--accent);
		translate: -50% 0;
	}

	.handle::after {
		content: '';
		position: absolute;
		top: 50%;
		left: 50%;
		width: 40px;
		height: 40px;
		background: var(--accent);
		translate: -50% -50%;
		clip-path: polygon(0 50%, 35% 15%, 35% 38%, 65% 38%, 65% 15%, 100% 50%, 65% 85%, 65% 62%, 35% 62%, 35% 85%);
	}

	input {
		margin: 0;
		opacity: 0;
		cursor: ew-resize;
	}
</style>
