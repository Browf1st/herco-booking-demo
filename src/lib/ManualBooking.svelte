<script lang="ts">
 import {resolve}from '$app/paths';import{page}from '$app/state';import ServerBooking from './ServerBooking.svelte';import ActionIcon from './ActionIcon.svelte';
 let email=$state(''),customer=$state<{id:string;email:string}>(),busy=$state(false),message=$state('');
 async function lookup(event:SubmitEvent){event.preventDefault();if(busy)return;busy=true;message='';try{const r=await fetch(resolve('/api/staff/manual-booking'),{method:'POST',headers:{'content-type':'application/json',accept:'application/json'},body:JSON.stringify({action:'lookup',email:email.trim()})});const data=await r.json();if(!r.ok)throw Error(data.message??'Could not find this verified customer.');customer=data;}catch(e){message=e instanceof Error?e.message:'Could not look up the customer.';}finally{busy=false;}}
</script>
{#if customer}
 <div class="wrap row customer-selection"><p>Booking for <strong>{customer.email}</strong></p><button class="btn sm ghost" onclick={()=>customer=undefined}><ActionIcon name="edit"/>Change customer</button></div>
 {#key customer.id + page.url.search}<ServerBooking manualCustomer={customer} walkIn={page.url.searchParams.get('walk-in')==='1'}/>{/key}
{:else}
 <section class="section wrap stack lookup"><h1>Manual booking</h1><form class="card stack" onsubmit={lookup}><h2>Find the customer</h2><p>The customer needs a verified HERCO account. Enter their full email address.</p><label>Customer email<input type="email" bind:value={email} maxlength="254" required disabled={busy}/></label>{#if message}<p role="alert">{message}</p>{/if}<div><button class="btn" disabled={busy}><ActionIcon name="search"/>{busy?'Checking…':'Find verified account'}</button></div></form></section>
{/if}
<style>.lookup{max-width:680px}.lookup h2{font-size:1.5rem}.customer-selection{padding-block:1rem;justify-content:space-between}</style>
