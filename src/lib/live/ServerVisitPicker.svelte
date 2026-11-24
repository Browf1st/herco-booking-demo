<script lang="ts">
 import ActionIcon from '../shared/ActionIcon.svelte';
 import AvailabilityCalendar from '../shared/AvailabilityCalendar.svelte';
 import { resolve } from '$app/paths';
 import { fmtDate, fmtSlot, today } from '../shared/dates';
 import { hourText } from '../shared/schedule-hours';
 type Slot = {visit_date:string;visit_hour:number|null;status:string;openHour:number|null;closeHour:number|null;closed:boolean};
 let {date=$bindable(''),hour=$bindable(''),days=[0,1,2,3,4,5,6],disabled=false}: {date?:string;hour?:string;days?:number[];disabled?:boolean}=$props();
 let slots=$state<Slot[]>([]), loading=$state(false), issue=$state('');
 let request=0;
 const allows=(day:string)=>days.includes(new Date(day+'T00:00:00Z').getUTCDay());
 const statusFor=(day:string)=>slots.some(s=>s.visit_date===day&&s.status==='open')?'open':'closed';
 const times=$derived(slots.filter(s=>s.visit_date===date&&s.status==='open'&&allows(date)));
 const info=$derived(slots.find(s=>s.visit_date===date));
 const hours=$derived(info&&!info.closed&&info.openHour!==null&&info.closeHour!==null?'Open '+hourText(info.openHour)+' to '+hourText(info.closeHour)+(date===today()?' today':''):'');
 async function month(from:string,to:string){const id=++request;loading=true;issue='';try{const r=await fetch(resolve('/api/availability')+'?'+new URLSearchParams({from,to}));if(!r.ok)throw Error();const data=await r.json();if(id===request)slots=data;}catch{if(id===request){slots=[];issue='Could not load available visits. Change month to retry.';}}finally{if(id===request)loading=false;}}
</script>
<div class="visit-picker">
 <div class="stack"><AvailabilityCalendar selected={date} {allows} {statusFor} onmonth={month} onpick={selected=>{if(!disabled){date=selected;hour='';}}}/></div>
 <div class="stack"><div><strong class="times-title">Available times</strong><p class="small muted">Philippine time{hours?' · '+hours:''}</p></div>
 {#if loading}<p role="status">Loading available visits…</p>{:else if issue}<p role="alert">{issue}</p>{:else if times.length}<div class="time-grid" role="group" aria-label={'Available times for '+fmtDate(date)}>{#each times as time(time.visit_hour)}<button type="button" class="time" {disabled} aria-pressed={hour===String(time.visit_hour)} onclick={()=>hour=String(time.visit_hour)}><ActionIcon name="clock"/>{fmtSlot(time.visit_hour+':00')}</button>{/each}</div>{:else if date&&info?.closed}<p class="error">Closed on this date. Please pick another day.</p>{:else if date}<p class="error">No times are available. Choose another date.</p>{:else}<p class="small muted">Choose a date to see available times.</p>{/if}
 </div>
</div>
<style>
 .visit-picker{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,235px),1fr));align-items:start;gap:16px}.times-title{text-transform:uppercase;letter-spacing:.04em;font-size:.85rem}.time-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}.time{font:inherit;border:1px solid var(--line);background:var(--panel);color:var(--text);padding:9px 6px;border-radius:9px;cursor:pointer}.time:hover,.time[aria-pressed='true']{background:var(--panel-2);border-color:var(--accent);color:var(--accent)}.time[aria-pressed='true']{background:color-mix(in srgb,var(--accent) 5%,var(--panel));box-shadow:inset 0 0 0 1px var(--accent);font-weight:700}
</style>
