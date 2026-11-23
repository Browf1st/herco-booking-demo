<script lang="ts">
	// "Nothing found" box with a button that clears the filters.

	let { title, text, action, onaction }: { title: string; text: string; action: string; onaction: () => void } = $props();
</script>

<div class="card empty">
	<h3>{title}</h3>
	<p class="muted">{text}</p>
	<button type="button" class="btn sm ghost" onclick={onaction}>{action}</button>
</div>

<style>
	.empty { display: grid; justify-items: center; gap: .6rem; padding: 2rem 1rem; text-align: center; border-style: dashed; }
	h3 { font-size: 1.4rem; }
	p { max-width: 23rem; margin: 0; font-size: .9rem; }
</style>
