<script lang="ts">
	import ManualBooking from '#lib/live/ManualBooking.svelte';
	import { resolve } from '$app/paths';
</script>

{#if import.meta.env.MODE === 'worker'}
	<ManualBooking />
{:else}
	<section class="section wrap stack">
		<h1>Manual booking</h1>
		<div><a class="btn sm" href={resolve('/book?manual=1')}>Open demo booking</a></div>
	</section>
{/if}
