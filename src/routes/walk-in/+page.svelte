<script lang="ts">
	import ServerBooking from '#lib/ServerBooking.svelte';
	import { resolve } from '$app/paths';
</script>

{#if import.meta.env.MODE === 'worker'}
	<ServerBooking walkIn />
{:else}
	<section class="section wrap stack">
		<h1>Walk in today</h1>
		<div><a class="btn sm" href={resolve('/book?walk-in=1')}>Open demo walk-in</a></div>
	</section>
{/if}
