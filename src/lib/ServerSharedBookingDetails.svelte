<script lang="ts">
 import {onMount} from 'svelte';import {resolve} from '$app/paths';
 let {bookingId}:{bookingId:string}=$props();
 let shared=$state<{note:string;photoCount:number}>(),error=$state('');
 async function load(){error='';try{const r=await fetch(resolve('/api/bookings/shared')+'?booking='+encodeURIComponent(bookingId));if(!r.ok)throw Error();shared=await r.json();}catch{error='Shared shop notes and photos are temporarily unavailable.';}}
 onMount(()=>{void load();});
</script>
{#if shared?.note}<p class="note">Note from the shop: {shared.note}</p>{/if}
{#if shared?.photoCount}<div class="cols">{#each Array(shared.photoCount) as _,i}<img src={resolve('/api/bookings/shared-photo')+'?'+new URLSearchParams({booking:bookingId,photo:String(i)})} alt={'Shared completion photo '+(i+1)} loading="lazy"/>{/each}</div>{/if}
{#if error}<p role="alert">{error}</p><button class="btn sm ghost" onclick={load}>Retry shared details</button>{/if}
<style>img{width:100%;max-height:220px;object-fit:contain;background:var(--panel-2);border-radius:6px}.note{white-space:pre-wrap}</style>
