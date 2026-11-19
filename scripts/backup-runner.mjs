import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createWriteStream } from 'node:fs';
import { mkdtemp, realpath, writeFile } from 'node:fs/promises';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';
import { createInterface } from 'node:readline';
import { Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath } from 'node:url';
import { runMediaRecovery } from './recovery-media.mjs';

function privateWebhook(value) {
	try {
		const url = new URL(value);
		return url.protocol === 'https:' && !url.username && !url.password ? url.href : null;
	} catch {
		return null;
	}
}

function waitForChild(child) {
	return new Promise(resolve => {
		child.once('error', () => resolve(false));
		child.once('close', code => resolve(code === 0));
	});
}

async function databaseSnapshot(start, env) {
	const child = start('psql', ['-X', '-q', '-A', '-t', '-w', '-v', 'ON_ERROR_STOP=1'], {
		env, stdio: ['pipe', 'pipe', 'ignore'], windowsHide: true
	});
	const completed = waitForChild(child);
	const lines = createInterface({ input: child.stdout, crlfDelay: Infinity });
	const cursor = lines[Symbol.asyncIterator]();
	child.stdin.on('error', () => child.kill());
	try {
		child.stdin.write(String.raw`
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT pg_export_snapshot();
SELECT to_char(transaction_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
SELECT to_jsonb(files.path)::text FROM (
  SELECT DISTINCT path FROM herco_private.booking_completion c CROSS JOIN LATERAL unnest(c.photo_paths) AS path
) files ORDER BY files.path COLLATE "C";
\echo HERCO_END_PHOTO_SNAPSHOT
`);
		const id = (await cursor.next()).value?.trim();
		if (!id || !/^[a-f0-9]+-[a-f0-9]+-\d+$/iu.test(id)) throw new Error('Could not export a database snapshot.');
		const recordedAt = (await cursor.next()).value?.trim();
		if (!recordedAt || !Number.isFinite(Date.parse(recordedAt))) throw new Error('Could not record the snapshot time.');
		const paths = [];
		while (true) {
			const line = await cursor.next();
			if (line.done) throw new Error('Could not read the photo paths from the snapshot.');
			if (line.value === 'HERCO_END_PHOTO_SNAPSHOT') break;
			const path = JSON.parse(line.value);
			if (typeof path !== 'string') throw new Error('The snapshot contains an invalid photo path.');
			paths.push(path);
		}
		return {
			id, paths, recordedAt,
			async close() {
				child.stdin.end('COMMIT;\n\\q\n');
				if (!await completed) throw new Error('The database snapshot connection ended unexpectedly.');
			},
			cancel() { child.kill(); }
		};
	} catch (failure) {
		child.kill();
		throw failure;
	}
}

async function writeDatabaseArchive(start, env, snapshot, archive) {
	const dump = start('pg_dump', ['--no-password', '--format=custom', '--snapshot=' + snapshot], {
		env, stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true
	});
	const encrypted = start('age', ['--encrypt', '--recipient', env.HERCO_BACKUP_AGE_RECIPIENT], {
		env, stdio: ['pipe', 'pipe', 'ignore'], windowsHide: true
	});
	const digest = createHash('sha256');
	const tee = new Transform({
		transform(chunk, _encoding, next) {
			digest.update(chunk);
			next(null, chunk);
		}
	});
	try {
		const [dumpOk, encryptionOk] = await Promise.all([
			waitForChild(dump), waitForChild(encrypted),
			pipeline(dump.stdout, encrypted.stdin),
			pipeline(encrypted.stdout, tee, createWriteStream(archive, { flags: 'wx', mode: 0o600 }))
		]);
		if (!dumpOk || !encryptionOk) throw new Error('Database export or encryption failed.');
		return digest.digest('hex');
	} catch (failure) {
		dump.kill();
		encrypted.kill();
		throw failure;
	}
}

export async function runScheduledBackup(env, dependencies = {}) {
	if ((env.HERCO_BACKUP_MODE ?? 'disabled') === 'disabled') return { state: 'disabled' };
	const start = dependencies.spawn ?? spawn;
	const fetchRequest = dependencies.fetch ?? fetch;
	const exportMedia = dependencies.recoverMedia ?? runMediaRecovery;
	const alert = privateWebhook(env.HERCO_BACKUP_ALERT_WEBHOOK);
	let stage = 'configuration';
	let snapshot;
	try {
		if (env.HERCO_BACKUP_MODE !== 'active' || !env.HERCO_BACKUP_DIRECTORY ||
			!/^age1[023456789acdefghjklmnpqrstuvwxyz]{58}$/u.test(env.HERCO_BACKUP_AGE_RECIPIENT ?? '') || !alert ||
			!env.PGHOST || !env.PGDATABASE || !env.PGUSER || env.PGSSLMODE !== 'verify-full') {
			throw new Error('Configure runner paths, encryption, verified TLS, and the backup alert webhook.');
		}
		const parent = await realpath(env.HERCO_BACKUP_DIRECTORY);
		const workspace = await realpath(fileURLToPath(new URL('../', import.meta.url)));
		const location = relative(workspace, parent);
		if (location !== '..' && !location.startsWith('..' + sep) && !isAbsolute(location)) {
			throw new Error('Store the backup outside the repo.');
		}
		const startedAt = new Date().toISOString();
		const output = await mkdtemp(join(parent, 'herco-' + startedAt.replace(/[:.]/gu, '-') + '-'));
		const databaseEnv = { ...env, PGCONNECT_TIMEOUT: env.PGCONNECT_TIMEOUT ?? '15' };
		stage = 'database_snapshot';
		snapshot = await databaseSnapshot(start, databaseEnv);
		stage = 'database_archive';
		const databaseSha256 = await writeDatabaseArchive(start, databaseEnv, snapshot.id, join(output, 'database.dump.age'));
		await snapshot.close();
		const { paths, recordedAt: snapshotAt } = snapshot;
		snapshot = undefined;
		stage = 'media_archive';
		const media = await exportMedia('backup', join(output, 'completion-photos'), env, fetchRequest, paths);
		if (media.state !== 'backup_verified' || media.objects !== paths.length) throw new Error('Media archive is incomplete.');
		stage = 'pairing_receipt';
		await writeFile(join(output, 'receipt.json'), JSON.stringify({
			startedAt, snapshotAt, finishedAt: new Date().toISOString(), databaseSha256, linkedPhotos: media.objects
		}, null, 2), { flag: 'wx', mode: 0o600 });
		return { state: 'backup_pair_complete', output, linkedPhotos: media.objects };
	} catch {
		snapshot?.cancel();
		let alerted = false;
		if (alert) {
			try {
				const response = await fetchRequest(alert, {
					method: 'POST', headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ service: 'herco', job: 'backup', state: 'failed', stage }),
					signal: AbortSignal.timeout(10000), redirect: 'error'
				});
				alerted = response.ok;
			} catch {
				// The process also exits nonzero so the runner can alert when the webhook is unreachable.
			}
		}
		return { state: 'backup_failed', stage, alerted };
	}
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const result = await runScheduledBackup(process.env);
	console.log(JSON.stringify(result));
	if (result.state === 'backup_failed') process.exitCode = 1;
}
