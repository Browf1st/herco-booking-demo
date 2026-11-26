import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, readdir, access } from 'node:fs/promises';
import { rewardStatus } from '../src/lib/shared/reward-receipt.ts';
const root = new URL('../', import.meta.url);
const read = path => readFile(new URL(path, root), 'utf8');
async function files(path) {
 const entries = await readdir(new URL(path, root), { withFileTypes: true });
 return (await Promise.all(entries.map(entry => entry.isDirectory() ? files(path + '/' + entry.name) : [path + '/' + entry.name]))).flat();
}
test('live screens and shared helpers have no demo imports or build-mode gates', async () => {
 for (const path of [...await files('src/routes'), ...await files('src/lib/live'), ...await files('src/lib/shared')]) {
  if (path.startsWith('src/routes/api/') || !/\.(svelte|ts)$/.test(path)) continue;
  const source = await read(path);
  assert.doesNotMatch(source, /(?:#lib\/demo|\.\.\/demo\/|import\.meta\.env\.MODE)/, path);
 }
 await assert.rejects(access(new URL('src/lib/demo', root)));
});
test('only the Worker build and budgets remain', async () => {
 const pkg = JSON.parse(await read('package.json'));
 assert.equal(pkg.scripts['build:worker'], 'vite build --mode worker');
 assert.equal(pkg.scripts.build, undefined);
 assert.equal(pkg.devDependencies['@sveltejs/adapter-static'], undefined);
 assert.doesNotMatch(await read('vite.config.ts'), /adapter-static|BASE_PATH/);
 assert.doesNotMatch(await read('scripts/performance-budget.mjs'), /directory: 'build'|demo: \{/);
 await assert.rejects(access(new URL('.github/workflows/deploy.yml', root)));
});
test('live customer and staff navigation retains shared header styling', async () => {
 const layout = await read('src/routes/+layout.svelte');
 for (const selector of ['.book-menu', '.book-options', '.menu-trigger', '.account-slot', '.main-nav', '.admin-sections', '.owner-options']) assert.ok(layout.includes(selector), selector);
 assert.doesNotMatch(layout, /selectDemoView|switchStaffSession|Demo views/);
 assert.match(layout, /refreshWorkerNavigation/);
 assert.match(layout, /\/api\/auth\/contact/);
});
test('shared reward receipt status preserves pending, approved, issued and claimed labels', () => {
 for (const [status, label] of [['pending', 'Pending for approval'], ['approved', 'Approved'], ['issued', 'Approved'], ['claimed', 'Claimed']]) assert.equal(rewardStatus({ status }), label);
});
