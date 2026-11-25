<script lang="ts">
 import {onMount} from 'svelte';import {resolve} from '$app/paths';import {today,addDays} from '#lib/shared/dates.ts';import ActionIcon from '#lib/shared/ActionIcon.svelte';
 type Stock={id:string;name:string;unit:string;category:string;minimum:number;quantity:number;revision:number;supplier:string|null;storage_location:string|null;unit_cost:number|null;billing_rate:number|null;capacity:number|null};
 type Activity={request_id:string;operation:string;recorded_at:string;actor_name:string;input:{reason?:string};before_value:Stock|null;after_value:Stock};
 type Inventory={canManage:boolean;items:Stock[];recent:Activity[];options:{kind:'unit'|'category';name:string}[]};
 let inventory=$state<Inventory>();let loading=$state(true);let busy=$state(false);let message=$state('');let notice=$state('');let editing=$state<Stock>();let moving=$state<Stock>();
 let name=$state('');let unit=$state('');let category=$state('');let supplier=$state('');let location=$state('');let unitCost=$state<number>();let billingRate=$state<number>();let capacity=$state<number>();let minimum=$state<number>(0);let quantity=$state<number>(0);let adjustment=$state<number>(1);let stockMode=$state<'add'|'use'>('add');let reason=$state('');
 let stockSearch=$state('');let categoryFilter=$state('');let stockFilter=$state('all');let stockPage=$state(1);let historyPage=$state(1);let historyItem=$state('');let historyFrom=$state(addDays(today(),-29));let historyThrough=$state(today());
 let itemDialog:HTMLDialogElement;let stockDialog:HTMLDialogElement;let optionDialog:HTMLDialogElement;let optionKind=$state<'unit'|'category'>('unit');let renaming=$state(false);let previousOption=$state('');let optionName=$state('');let newId='';const attempts=new Map<string,string>();const pageSize=10;
 const money=(n:number)=>new Intl.NumberFormat('en-PH',{style:'currency',currency:'PHP'}).format(n);const stamp=(s:string)=>new Date(s).toLocaleString('en-PH',{timeZone:'Asia/Manila',hour12:true});
 const units=$derived(inventory?.options.filter(o=>o.kind==='unit').map(o=>o.name)??[]);const categories=$derived(inventory?.options.filter(o=>o.kind==='category').map(o=>o.name)??[]);const optionValues=$derived(optionKind==='unit'?units:categories);
 const stockStatus=(s:Stock)=>s.quantity===0?'out':s.quantity<=s.minimum?'low':'healthy';
 const visible=$derived((inventory?.items??[]).filter(s=>(s.name+' '+s.supplier+' '+s.storage_location).toLowerCase().includes(stockSearch.toLowerCase())&&(!categoryFilter||s.category===categoryFilter)&&(stockFilter==='all'||stockStatus(s)===stockFilter)));
 const pageItems=$derived(visible.slice((stockPage-1)*pageSize,stockPage*pageSize));
 const history=$derived((inventory?.recent??[]).filter(e=>!historyItem||e.after_value.id===historyItem));
 async function load(){loading=true;message='';try{const r=await fetch(resolve('/api/inventory')+'?'+new URLSearchParams({from:historyFrom,through:historyThrough,...(historyItem?{item:historyItem}:{})}));if(!r.ok)throw Error((await r.json()).message??'Inventory unavailable.');inventory=await r.json();}catch(e){message=e instanceof Error?e.message:'Inventory unavailable.';}finally{loading=false;}}
 function edit(item?:Stock){editing=item;newId=item?.id??crypto.randomUUID();name=item?.name??'';unit=item?.unit??units[0]??'';category=item?.category??'';supplier=item?.supplier??'';location=item?.storage_location??'';unitCost=item?.unit_cost??undefined;billingRate=item?.billing_rate??undefined;capacity=item?.capacity??undefined;minimum=item?.minimum??0;quantity=0;message='';itemDialog.showModal();}
 function move(item?:Stock,mode:'add'|'use'='add'){moving=item??inventory?.items[0];stockMode=mode;adjustment=1;reason='';message='';stockDialog.showModal();}
 function openOptions(kind:'unit'|'category'='unit'){optionKind=kind;renaming=false;previousOption='';optionName='';message='';optionDialog.showModal();}
 async function write(payload:Record<string,unknown>){if(busy)return false;busy=true;message=notice='';const fingerprint=JSON.stringify(payload);const requestId=attempts.get(fingerprint)??crypto.randomUUID();attempts.set(fingerprint,requestId);try{const r=await fetch(resolve('/api/inventory'),{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...payload,requestId})});if(!r.ok)throw Error((await r.json()).message??'Could not save inventory.');attempts.delete(fingerprint);await load();notice='Inventory updated.';return true;}catch(e){message=e instanceof Error?e.message:'Could not save inventory.';return false;}finally{busy=false;}}
 async function saveItem(e:SubmitEvent){e.preventDefault();const details={name,unit,category,minimum,supplier,storage_location:location,unit_cost:unitCost??null,billing_rate:billingRate??null,capacity:capacity??null,...(editing?{revision:editing.revision}:{quantity})};if(await write({operation:editing?'edit':'create',stockId:newId,details}))itemDialog.close();}
 async function saveStock(e:SubmitEvent){e.preventDefault();if(moving&&await write({operation:'move',stockId:moving.id,details:{delta:stockMode==='add'?adjustment:-adjustment,reason:reason.trim()|| (stockMode==='add'?'Supplier delivery':'Workshop usage')}}))stockDialog.close();}
 async function saveOption(e:SubmitEvent){e.preventDefault();if(await write({operation:'option',kind:optionKind,previous:renaming?previousOption:null,name:optionName}))optionDialog.close();}
 onMount(()=>{if(import.meta.env.MODE==='worker')void load();else loading=false;});
</script>
<svelte:head><title>Inventory | HERCO</title></svelte:head>
{#snippet stateBadge(item: Stock)}
 {@const status = stockStatus(item)}
 <span class="badge" data-status={status === 'healthy' ? 'done' : status === 'low' ? 'pending' : 'cancelled'}>
  {status === 'healthy' ? 'Healthy' : status === 'low' ? 'Low stock' : 'Out of stock'}
 </span>
{/snippet}

{#snippet stockLevel(item: Stock)}
 <div class="stock-level" data-level={stockStatus(item)}>
  <div><strong>{item.quantity} {item.unit}</strong><span class="muted"> / {item.capacity === null ? 'No capacity set' : item.capacity + ' ' + item.unit}</span></div>
  {#if item.capacity !== null && item.capacity > 0}
   {@const percent = Math.round(item.quantity / item.capacity * 100)}
   <div class="capacity-meter">
    <meter aria-label={'Storage capacity used for ' + item.name} min="0" max={item.capacity} value={Math.min(item.quantity, item.capacity)}></meter>
    <span>{percent}%</span>
   </div>
  {/if}
 </div>
{/snippet}

{#snippet itemDetails(item: Stock, showLocation = true)}
 {#if showLocation && item.storage_location}<span class="location">{item.storage_location}</span>{/if}
 {#if item.supplier}<p>Supplier · {item.supplier}</p>{/if}
 {#if item.unit_cost !== null}<p>Unit cost · {money(item.unit_cost)}</p>{/if}
 {#if item.billing_rate !== null}<p>Billing rate · {money(item.billing_rate)}</p>{/if}
{/snippet}

{#snippet itemActions(item: Stock)}
 <div class="item-actions">
  <button class="btn sm ghost" aria-label={'Stock in for ' + item.name} onclick={() => move(item, 'add')}><ActionIcon name="in"/>Stock in</button>
  <button class="btn sm ghost" disabled={!item.quantity} aria-label={'Stock out for ' + item.name} onclick={() => move(item, 'use')}><ActionIcon name="out"/>Stock out</button>
  <button class="btn sm ghost" aria-label={'Edit item ' + item.name} onclick={() => edit(item)}><ActionIcon name="edit"/>Edit</button>
 </div>
{/snippet}

<section class="section wrap stack inventory">
 <div class="stock-heading row between">
  <h1>Stock on hand</h1>
  {#if inventory?.canManage}
   <div class="stock-actions row">
    <button class="btn sm" onclick={() => edit()}><ActionIcon name="add"/>Add supply</button>
    <button class="btn sm ghost" disabled={!inventory.items.length} onclick={() => move()}><ActionIcon name="adjust"/>Update existing stock</button>
    <button class="btn sm ghost" onclick={() => openOptions()}><ActionIcon name="box"/>Manage units and categories</button>
   </div>
  {/if}
 </div>
 {#if message}<p class="error" role="alert">{message}</p>{/if}
 {#if notice}<p role="status">{notice}</p>{/if}
 {#if loading}
  <p role="status">Loading inventory…</p>
 {:else if inventory}
  <dl class="inventory-metrics" aria-label="Inventory overview">
   <div><dt><ActionIcon name="box"/>Total items</dt><dd>{inventory.items.length}</dd></div>
   <div class="healthy"><dt><ActionIcon name="check"/>Healthy stock</dt><dd>{inventory.items.filter(i => stockStatus(i) === 'healthy').length}</dd></div>
   <div class="low"><dt><ActionIcon name="adjust"/>Low stock</dt><dd>{inventory.items.filter(i => stockStatus(i) === 'low').length}</dd></div>
   <div class="out"><dt><ActionIcon name="block"/>Out of stock</dt><dd>{inventory.items.filter(i => stockStatus(i) === 'out').length}</dd></div>
  </dl>
  <section class="card stock-filters" aria-label="Stock filters">
   <label class="stock-search">Search supplies
    <span class="search-field"><ActionIcon name="search"/><input type="search" bind:value={stockSearch} oninput={() => stockPage = 1} placeholder="e.g. Ceramic coating"/></span>
   </label>
   <label>Category
    <select bind:value={categoryFilter} onchange={() => stockPage = 1}><option value="">All categories</option>{#each categories as c}<option>{c}</option>{/each}</select>
   </label>
   <label>Stock status
    <select bind:value={stockFilter} onchange={() => stockPage = 1}><option value="all">All stock</option><option value="healthy">Healthy stock</option><option value="low">Low stock</option><option value="out">Out of stock</option></select>
   </label>
  </section>
  <section class="stock-results" aria-label="Inventory items">
   {#if pageItems.length}
    <div class="desktop-stock">
     <table aria-label="Stock on hand">
      <thead><tr>
       <th scope="col">Item &amp; details</th><th scope="col">Category</th><th scope="col">Stock &amp; capacity</th>
       <th scope="col">Status</th><th scope="col">Reorder threshold</th>
       {#if inventory.canManage}<th scope="col">Inventory actions</th>{/if}
      </tr></thead>
      <tbody>
       {#each pageItems as item (item.id)}
        <tr>
         <th scope="row"><strong>{item.name}</strong><div class="item-details">{@render itemDetails(item)}</div></th>
         <td>{item.category || 'Uncategorized'}</td>
         <td>{@render stockLevel(item)}</td>
         <td>{@render stateBadge(item)}</td>
         <td>{item.minimum} {item.unit}</td>
         {#if inventory.canManage}<td>{@render itemActions(item)}</td>{/if}
        </tr>
       {/each}
      </tbody>
     </table>
    </div>
    <div class="mobile-stock">
     {#each pageItems as item (item.id)}
      <article class="card stock-item">
       <div class="item-heading">
        <div><div class="item-title"><h2>{item.name}</h2>{#if item.storage_location}<span class="location">{item.storage_location}</span>{/if}</div><p class="muted">{item.category || 'Uncategorized'}</p></div>
        {@render stateBadge(item)}
       </div>
       <div class="mobile-level"><span class="field-caption">Stock &amp; capacity</span>{@render stockLevel(item)}</div>
       <div class="item-details mobile-details">
        <div><span class="field-caption">Reorder threshold</span><p>{item.minimum} {item.unit}</p></div>
        <div>{@render itemDetails(item, false)}</div>
       </div>
       {#if inventory.canManage}{@render itemActions(item)}{/if}
      </article>
     {/each}
    </div>
   {:else}
    <p class="card">No inventory items match these filters.</p>
   {/if}
   <div class="row stock-pagination">
    <span class="muted">{visible.length} of {inventory.items.length} items shown</span>
    <nav class="row pagination" aria-label="Stock on hand pagination">
     <button class="btn sm ghost" disabled={stockPage <= 1} onclick={() => stockPage--}>Previous</button>
     <span>Page {stockPage} of {Math.max(1, Math.ceil(visible.length / pageSize))}</span>
     <button class="btn sm ghost" disabled={stockPage * pageSize >= visible.length} onclick={() => stockPage++}>Next</button>
    </nav>
   </div>
  </section>
  <details class="card stock-history" open>
   <summary><ActionIcon name="history"/> Stock history</summary>
   <form class="history-filters" onsubmit={e => { e.preventDefault(); historyPage = 1; void load(); }}>
    <label>Filter stock history
     <select bind:value={historyItem}><option value="">All items</option>{#each inventory.items as i (i.id)}<option value={i.id}>{i.name}</option>{/each}</select>
    </label>
    <label>From<input type="date" bind:value={historyFrom} required/></label>
    <label>Through<input type="date" bind:value={historyThrough} min={historyFrom} required/></label>
    <button class="btn sm ghost">Apply filters</button>
   </form>
   {#each history.slice((historyPage - 1) * pageSize, historyPage * pageSize) as e (e.request_id)}
    <article class="history-row">
     <strong>{e.after_value.name} · {e.operation === 'move' ? 'Stock adjusted' : e.operation === 'create' ? 'Item created' : 'Item edited'}</strong>
     <p>{e.before_value?.quantity ?? 0} → {e.after_value.quantity} {e.after_value.unit}{e.input.reason ? ' · ' + e.input.reason : ''}</p>
     <p class="small muted">{e.actor_name} · {stamp(e.recorded_at)} PH time</p>
    </article>
   {:else}<p>No stock history in this period.</p>{/each}
   <div class="row history-footer">
    <p class="small muted">Up to 1,000 movements in the selected period.</p>
    <nav class="row pagination" aria-label="Stock history pagination">
     <button class="btn sm ghost" disabled={historyPage <= 1} onclick={() => historyPage--}>Previous</button>
     <span>Page {historyPage}</span>
     <button class="btn sm ghost" disabled={historyPage * pageSize >= history.length} onclick={() => historyPage++}>Next</button>
    </nav>
   </div>
  </details>
 {:else}
  <button class="btn sm ghost" onclick={load}>Try again</button>
 {/if}
</section>
<dialog class="inventory-form" bind:this={itemDialog} aria-labelledby="item-title"><form class="stack" onsubmit={saveItem}><div class="row between"><h3 id="item-title">{editing?'Edit inventory item':'Create new inventory item'}</h3><button class="close-dialog" type="button" aria-label="Close inventory popup" onclick={()=>itemDialog.close()}><ActionIcon name="close"/></button></div><label>Item name<input bind:value={name} maxlength="120" required/></label><div class="cols"><label>Category (optional)<button class="inventory-option-link" type="button" onclick={()=>openOptions('category')}>New category</button><select bind:value={category}><option value="">Uncategorized</option>{#each categories as c}<option>{c}</option>{/each}</select></label><label>Unit of measure<button class="inventory-option-link" type="button" onclick={()=>openOptions('unit')}>New unit</button><select bind:value={unit} required><option value="">Select unit</option>{#each units as u}<option>{u}</option>{/each}</select></label></div><fieldset class="inventory-fields"><legend>Stock levels</legend><div class="cols stock-level-fields">{#if !editing}<label>Opening stock<input type="number" bind:value={quantity} min="0" step=".001" required/></label>{/if}<label>Reorder threshold<input type="number" bind:value={minimum} min="0" step=".001" required/></label><label>Storage capacity (optional)<input type="number" bind:value={capacity} min="0" step=".001"/></label></div></fieldset><fieldset class="inventory-fields"><legend>Supplier and costs</legend><div class="cols"><label>Supplier<input bind:value={supplier} maxlength="120"/></label><label>Storage location<input bind:value={location} maxlength="120"/></label><label>Unit cost (₱)<input type="number" bind:value={unitCost} min="0" step=".01"/></label><label>Billing rate (₱)<input type="number" bind:value={billingRate} min="0" step=".01"/></label></div></fieldset>{#if message}<p role="alert">{message}</p>{/if}<div class="row inventory-form-footer"><button class="btn sm ghost" type="button" onclick={()=>itemDialog.close()}>Cancel</button><button class="btn sm" disabled={busy}><ActionIcon name="save"/>{editing?'Save changes':'Create inventory item'}</button></div></form></dialog>
<dialog bind:this={stockDialog} aria-labelledby="stock-title"><form class="stack" onsubmit={saveStock}><div class="row between"><h3 id="stock-title">{stockMode==='add'?'Add stock':'Record usage'}</h3><button class="close-dialog" type="button" aria-label="Close stock popup" onclick={()=>stockDialog.close()}><ActionIcon name="close"/></button></div><label>Item<select value={moving?.id??''} required onchange={e=>moving=inventory?.items.find(i=>i.id===e.currentTarget.value)}><option value="">Select item</option>{#each inventory?.items??[] as i(i.id)}<option value={i.id}>{i.name}</option>{/each}</select></label><label>Update type<select bind:value={stockMode}><option value="add">Add stock</option><option value="use">Record usage</option></select></label><label>Quantity {moving?'('+moving.unit+')':''}<input type="number" bind:value={adjustment} min=".001" step=".001" required/></label><label>Note (optional)<input bind:value={reason} maxlength="300" placeholder={stockMode==='add'?'e.g. Supplier delivery':'e.g. Ceramic coating service'}/></label>{#if message}<p role="alert">{message}</p>{/if}<div class="row"><button class="btn sm" disabled={busy}><ActionIcon name="save"/>{stockMode==='add'?'Add stock':'Save usage'}</button><button class="btn sm ghost" type="button" onclick={()=>stockDialog.close()}>Cancel</button></div></form></dialog>
<dialog bind:this={optionDialog} aria-labelledby="option-title"><form class="stack" onsubmit={saveOption}><h3 id="option-title">Manage units and categories</h3><div class="cols"><label>Type<select bind:value={optionKind} onchange={()=>{previousOption=optionName='';}}><option value="unit">Unit</option><option value="category">Category</option></select></label><label>Action<select bind:value={renaming}><option value={false}>Add new</option><option value={true}>Rename existing</option></select></label></div>{#if renaming}<label>Existing {optionKind}<select bind:value={previousOption} required onchange={e=>optionName=e.currentTarget.value}><option value="">Select</option>{#each optionValues as o}<option>{o}</option>{/each}</select></label>{/if}<label>{renaming?'New name':'Name'}<input bind:value={optionName} maxlength={optionKind==='unit'?30:60} required/></label>{#if message}<p role="alert">{message}</p>{/if}<div class="row"><button class="btn sm" disabled={busy}>Save</button><button class="btn sm ghost" type="button" onclick={()=>optionDialog.close()}>Cancel</button></div></form></dialog>
<style>
 .between { justify-content: space-between; }
 .inventory { width: 100%; max-width: 1280px; }
 .stock-heading { flex-wrap: wrap; gap: .65rem; align-items: center; }
 .stock-heading h1 { font-size: clamp(1.8rem, 5vw, 3.25rem); }
 .stock-actions { flex-wrap: wrap; gap: .5rem; }
 .inventory .btn { clip-path: none; border: 1px solid transparent; border-radius: 5px; gap: .3rem; padding-inline: .65rem; }
 .inventory .btn.ghost { border-color: var(--line); }
 .inventory-metrics { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .65rem; margin: 0; }
 .inventory-metrics > div { min-width: 0; border: 1px solid var(--line); border-radius: 6px; padding: .65rem; background: var(--panel); box-shadow: 0 1px 2px var(--card-shadow); }
 .inventory-metrics .healthy { color: var(--ok); background: var(--ok-bg); border-color: var(--ok-line); }
 .inventory-metrics .low { color: var(--warn); background: var(--warn-bg); border-color: var(--warn-line); }
 .inventory-metrics .out { color: var(--bad); background: var(--bad-bg); border-color: var(--bad-line); }
 .inventory-metrics dt { font: 700 .9rem var(--display); text-transform: uppercase; }
 .inventory-metrics dd { margin: .2rem 0 0; font: 800 1.65rem var(--display); }
 .stock-filters, .history-filters { display: grid; gap: .65rem; align-items: end; }
 .stock-filters { grid-template-columns: minmax(0, 2fr) repeat(2, minmax(0, 1fr)); }
 .stock-filters label, .history-filters label { min-width: 0; }
 .stock-filters input, .stock-filters select, .history-filters input, .history-filters select { min-width: 0; width: 100%; height: 48px; padding-block: 0; }
 .inventory .history-filters .btn { min-height: 48px; }
 .search-field { display: block; position: relative; }
 .search-field :global(svg) { position: absolute; top: 50%; left: .65rem; transform: translateY(-50%); color: var(--muted); pointer-events: none; }
 .search-field input { padding-inline-start: 2rem; }
 .stock-results, .stock-item { display: grid; gap: .7rem; min-width: 0; }
 .desktop-stock { border: 1px solid var(--line); border-radius: 6px; background: var(--panel); }
 table { width: 100%; table-layout: fixed; border-collapse: collapse; font-size: .88rem; }
 thead { background: var(--panel-2); color: var(--muted); font: 700 .9rem var(--display); text-transform: uppercase; }
 th, td { text-align: left; vertical-align: top; padding: .65rem; border-bottom: 1px solid var(--line); overflow-wrap: anywhere; }
 thead th:first-child { width: 23%; }
 thead th:nth-child(3) { width: 17%; }
 thead th:nth-child(4) { width: 14%; }
 thead th:nth-child(5):not(:last-child) { width: 10%; }
 thead th:nth-child(6) { width: 26%; text-align: right; }
 tbody tr:last-child > * { border-bottom: 0; }
 .item-details { color: var(--muted); font-size: .8rem; font-weight: 400; }
 .location { display: inline-block; border-radius: 4px; background: var(--panel-2); padding: 0 .35rem; }
 .stock-level { font-size: .85rem; overflow-wrap: anywhere; }
 .capacity-meter { display: flex; align-items: center; gap: .4rem; margin-top: .25rem; color: var(--muted); }
 .capacity-meter span { flex: none; white-space: nowrap; }
 meter { width: 100%; min-width: 0; height: .6rem; }
 meter::-webkit-meter-bar { background: var(--panel-2); border: none; }
 meter::-webkit-meter-optimum-value { background: var(--meter-color, var(--ok)); }
 meter::-moz-meter-bar { background: var(--meter-color, var(--ok)); }
 [data-level='low'] { --meter-color: var(--warn); }
 [data-level='out'] { --meter-color: var(--bad); }
 .item-actions { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: .35rem; }
 .item-actions .btn { font-size: .82rem; white-space: nowrap; }
 .badge { white-space: nowrap; }
 .mobile-stock { display: none; }
 .stock-pagination, .history-footer { justify-content: space-between; font-size: .85rem; }
 .pagination { justify-content: flex-end; margin-inline-start: auto; }
 .stock-history summary { cursor: pointer; font: 800 1.2rem var(--display); text-transform: uppercase; }
 .history-filters { grid-template-columns: minmax(0, 1.5fr) repeat(2, minmax(0, 1fr)) auto; margin-block: .8rem; }
 .history-row { padding-block: .65rem; border-top: 1px solid var(--line); overflow-wrap: anywhere; }
 .history-footer { margin-top: .65rem; }
 @media (max-width: 900px) {
  .desktop-stock { display: none; }
  .mobile-stock { display: grid; gap: .65rem; }
  .item-heading { display: flex; justify-content: space-between; align-items: flex-start; gap: .5rem; }
  .item-heading { border-bottom: 1px solid var(--line); padding-bottom: .5rem; }
  .item-heading > div { min-width: 0; overflow-wrap: anywhere; }
  .item-title { display: flex; flex-wrap: wrap; align-items: center; gap: .25rem; }
  .item-title .location { font-size: .75rem; }
  .stock-pagination { border: 1px solid var(--line); border-radius: 6px; background: var(--panel); padding: .5rem; }
  .item-heading h2 { font: 700 1rem/1.2 var(--body); text-transform: none; overflow-wrap: anywhere; }
  .item-heading p { font-size: .8rem; }
  .mobile-level { background: var(--panel-2); border-radius: 5px; padding: .5rem; }
  .mobile-level meter::-webkit-meter-bar { background: var(--panel); }
  .field-caption { font: 700 .8rem var(--display); text-transform: uppercase; color: var(--muted); }
  .mobile-details { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .5rem; }
  .mobile-details > div:empty { display: none; }
  .item-actions { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .inventory .btn { min-height: 44px; }
  .item-actions .btn { padding-inline: .2rem; white-space: normal; line-height: 1; text-align: center; }
 }
 @media (max-width: 650px) {
  .inventory { padding-block: 1.25rem; }
  .stock-heading h1 { font-size: clamp(1.45rem, 6.8vw, 1.8rem); }
  .stock-filters select { font-size: .85rem; }
  .inventory-metrics > div:is(.healthy, .low, .out) { background: var(--panel); }
  .inventory-metrics dt { display: flex; flex-direction: row-reverse; align-items: start; justify-content: space-between; gap: .25rem; }
  .inventory-metrics dt :global(svg) { background: var(--panel-2); padding: .2rem; border-radius: 4px; width: 1.4rem; height: 1.4rem; }
  .inventory-metrics dd { color: var(--text); }
  .inventory-metrics, .stock-filters, .history-filters { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .stock-search, .history-filters label:first-child, .history-filters button { grid-column: 1 / -1; }
  .history-filters button { justify-self: end; }
  .stock-filters, .stock-item, .stock-history { padding: .65rem; }
 }
 dialog{width:min(560px,calc(100vw - 32px));max-height:calc(100dvh - 48px);padding:24px;overflow:auto;border:1px solid var(--line);border-radius:12px;background:var(--panel);color:var(--text)}dialog.inventory-form{width:min(860px,calc(100vw - 32px))}dialog::backdrop{background:#000b}.close-dialog{display:grid;place-items:center;width:40px;height:40px;border:1px solid var(--line);border-radius:50%;background:var(--panel-2);color:var(--text)}.inventory-option-link{border:0;background:transparent;color:var(--accent);font:inherit;font-size:.8rem;cursor:pointer;text-align:left;padding:0}.inventory-fields{min-inline-size:0;margin:0;padding:.8rem;border:1px solid var(--line);border-radius:.4rem}.inventory-fields legend{padding-inline:.35rem;font-weight:700}.stock-level-fields label{background:var(--panel-2);padding:.6rem;border-radius:.3rem}.inventory-form-footer{justify-content:space-between;border-top:1px solid var(--line);padding-top:.75rem}
</style>
