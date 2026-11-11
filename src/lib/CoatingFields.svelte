<script lang="ts">
 import { canEnhance, finishes, parts, type Selection } from './coating';
 let { value = $bindable(), bike }: { value: Selection; bike: string } = $props();
 const wheelSizes = ['Not sure', ...Array.from({length: 13}, (_, i) => String(i + 10))];
</script>

<div class="stack">
 <div class="row">
  <label class="choice"><input type="checkbox" bind:checked={value.ceramic} /> Ceramic Coating</label>
  <label class="choice"><input type="checkbox" bind:checked={value.powder} /> Powder Coating</label>
 </div>
 {#if value.ceramic}
  <label>Ceramic finish
   <select bind:value={value.ceramicFinish}>
    {#each finishes as finish}<option value={finish} disabled={finish === 'Enhance' && !canEnhance(bike)}>{finish}{finish === 'Enhance' ? ' (red Honda ADV / PCX)' : ''}</option>{/each}
   </select>
  </label>
  {#if value.ceramicFinish === 'Enhance'}<label class="choice"><input type="checkbox" bind:checked={value.red} required /> My Honda ADV or PCX is red</label>{/if}
 {/if}
 {#if value.powder}
  <fieldset class="stack"><legend>Parts to powder coat</legend>
   <div class="cols">{#each parts as part}<label class="choice"><input type="checkbox" value={part} bind:group={value.powderParts} /> {part}</label>{/each}</div>
  </fieldset>
  {#if value.powderParts.includes(parts[0])}
   <div class="cols">
    <label>Front mag diameter (inches)<select bind:value={value.front}><option value="">No front mag</option>{#each wheelSizes as size}<option>{size}</option>{/each}</select></label>
    <label>Rear mag diameter (inches)<select bind:value={value.rear}><option value="">No rear mag</option>{#each wheelSizes as size}<option>{size}</option>{/each}</select></label>
   </div>
  {/if}
  <label>Powder colour or finish (optional)<input maxlength="100" bind:value={value.finish} placeholder="e.g. Satin bronze" /></label>
  <p class="small muted">The shop will inspect metal parts before confirming suitability and the quote.</p>
 {/if}
</div>

<style>
 fieldset { min-inline-size: 0; margin: 0; border: 1px solid var(--line); border-radius: 6px; }
 .choice { display: flex; align-items: center; gap: 8px; padding: 8px; color: var(--text); }
 input[type='checkbox'] { accent-color: var(--accent); width: 1rem; height: 1rem; }
</style>
