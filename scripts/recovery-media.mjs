import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { mkdir, readFile, realpath, writeFile } from 'node:fs/promises';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const bucket = 'herco-completion';
const header = Buffer.from('HERCO-PHOTO-1\n');
const uuid = '[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}';
const pathFormat = new RegExp('^' + uuid + '/' + uuid + '/[a-f0-9-]{36}\\.(jpg|png|webp)$');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const imageTypes = { jpg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };

function project(value) {
	const url = new URL(value ?? '');
	if (url.protocol !== 'https:' || url.username || url.password || url.pathname !== '/' || url.search || url.hash) {
		throw new Error('Use the HTTPS origin of the authorized Supabase project.');
	}
	return url.origin;
}

function recoveryKey(value) {
	if (typeof value !== 'string' || !/^[A-Za-z0-9+/]{43}=$/u.test(value)) {
		throw new Error('Supply a 32-byte base64 HERCO_MEDIA_ENCRYPTION_KEY from the recovery secret store.');
	}
	return Buffer.from(value, 'base64');
}

function projectClient(url, secret, fetchRequest) {
	if (typeof secret !== 'string' || !secret.trim()) throw new Error('The recovery runner needs an authorized server credential.');
	return createClient(url, secret.trim(), {
		auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
		global: { fetch: (input, init) => fetchRequest(input, { ...init, signal: AbortSignal.timeout(30000) }) }
	});
}

function encrypt(bytes, key, label) {
	const nonce = randomBytes(12);
	const cipher = createCipheriv('aes-256-gcm', key, nonce);
	cipher.setAAD(Buffer.from(label));
	return Buffer.concat([header, nonce, cipher.update(bytes), cipher.final(), cipher.getAuthTag()]);
}

function decrypt(bytes, key, label) {
	const end = bytes.length - 16;
	if (end < header.length + 12 || !bytes.subarray(0, header.length).equals(header)) {
		throw new Error('The backup file format is invalid.');
	}
	const decipher = createDecipheriv('aes-256-gcm', key, bytes.subarray(header.length, header.length + 12));
	decipher.setAAD(Buffer.from(label));
	decipher.setAuthTag(bytes.subarray(end));
	return Buffer.concat([decipher.update(bytes.subarray(header.length + 12, end)), decipher.final()]);
}

async function linkedPaths(client) {
	const paths = [];
	let cursor = '';
	while (true) {
		const { data, error } = await client.rpc('herco_completion_backup_paths', { p_after_path: cursor, p_limit: 200 });
		if (error || !Array.isArray(data) || data.length > 200) throw new Error('Could not read the linked completion evidence list.');
		for (const item of data) {
			const path = item?.object_path;
			if (typeof path !== 'string' || !pathFormat.test(path) || path <= cursor) {
				throw new Error('The completion evidence list contains an invalid or unordered path.');
			}
			paths.push(path);
			cursor = path;
		}
		if (data.length < 200) return paths;
	}
}

async function readObject(storage, path) {
	const { data, error } = await storage.download(path);
	if (error || !data) throw new Error('Could not read a linked completion photo. The backup is incomplete.');
	return Buffer.from(await data.arrayBuffer());
}

function objectFile(directory, path) {
	return join(directory, digest(path) + '.enc');
}

async function verifyArchive(directory, key) {
	const encrypted = await readFile(join(directory, 'manifest.enc'));
	const manifest = JSON.parse(decrypt(encrypted, key, 'manifest').toString('utf8'));
	if (manifest?.version !== 1 || manifest.bucket !== bucket || !Array.isArray(manifest.objects)) {
		throw new Error('The recovery manifest is invalid.');
	}
	project(manifest.source);
	const seen = new Set();
	for (const entry of manifest.objects) {
		if (!entry || typeof entry.path !== 'string' || !pathFormat.test(entry.path) || seen.has(entry.path) ||
			!Number.isSafeInteger(entry.size) || entry.size < 1 || !/^[a-f0-9]{64}$/u.test(entry.sha256)) {
			throw new Error('The recovery manifest contains an invalid photo entry.');
		}
		seen.add(entry.path);
		const clear = decrypt(await readFile(objectFile(directory, entry.path)), key, entry.path);
		if (clear.length !== entry.size || digest(clear) !== entry.sha256) throw new Error('A recovery photo does not match its manifest.');
	}
	return manifest;
}

export async function runMediaRecovery(command, directory, env, fetchRequest = fetch, snapshotPaths) {
	const key = recoveryKey(env.HERCO_MEDIA_ENCRYPTION_KEY);
	const archive = resolve(directory);
	if (command === 'backup') {
		const source = project(env.HERCO_MEDIA_SOURCE_SUPABASE_URL);
		const client = projectClient(source, env.HERCO_MEDIA_SOURCE_SECRET_KEY, fetchRequest);
		const workspace = await realpath(fileURLToPath(new URL('../', import.meta.url)));
		const physicalArchive = join(await realpath(dirname(archive)), basename(archive));
		const location = relative(workspace, physicalArchive);
		if (location !== '..' && !location.startsWith('..' + sep) && !isAbsolute(location)) {
			throw new Error('Store backup artifacts outside the application checkout.');
		}
		const paths = snapshotPaths ?? await linkedPaths(client);
		if (paths.some((path, index) => typeof path !== 'string' || !pathFormat.test(path) ||
			(index > 0 && path <= paths[index - 1]))) {
			throw new Error('The database snapshot contains invalid or unordered photo paths.');
		}
		await mkdir(archive);
		const storage = client.storage.from(bucket);
		const objects = [];
		for (const path of paths) {
			const bytes = await readObject(storage, path);
			if (!bytes.length) throw new Error('A linked completion photo is empty. The backup is incomplete.');
			await writeFile(objectFile(archive, path), encrypt(bytes, key, path), { flag: 'wx', mode: 0o600 });
			objects.push({ path, size: bytes.length, sha256: digest(bytes) });
		}
		const manifest = Buffer.from(JSON.stringify({ version: 1, source, bucket, createdAt: new Date().toISOString(), objects }));
		await writeFile(join(archive, 'manifest.enc'), encrypt(manifest, key, 'manifest'), { flag: 'wx', mode: 0o600 });
		await verifyArchive(archive, key);
		return { state: 'backup_verified', objects: objects.length };
	}

	const manifest = await verifyArchive(archive, key);
	if (command === 'verify') return { state: 'archive_verified', objects: manifest.objects.length };
	if (command !== 'restore' || env.HERCO_MEDIA_RESTORE_ACCEPT !== 'isolated-restore-drill') {
		throw new Error('Restore requires an explicitly authorized isolated recovery drill.');
	}
	const destination = project(env.HERCO_MEDIA_TARGET_SUPABASE_URL);
	if (destination === manifest.source) throw new Error('Choose an isolated project distinct from the backup source.');
	const client = projectClient(destination, env.HERCO_MEDIA_TARGET_SECRET_KEY, fetchRequest);
	const paths = await linkedPaths(client);
	if (paths.length !== manifest.objects.length || paths.some((path, index) => path !== manifest.objects[index].path)) {
		throw new Error('The destination database and encrypted photo manifest differ. Check the paired database restore.');
	}
	const storage = client.storage.from(bucket);
	let uploaded = 0;
	for (const entry of manifest.objects) {
		const bytes = decrypt(await readFile(objectFile(archive, entry.path)), key, entry.path);
		if (bytes.length !== entry.size || digest(bytes) !== entry.sha256) throw new Error('A recovery photo does not match its manifest.');
		const { error } = await storage.upload(entry.path, bytes, {
			upsert: false, contentType: imageTypes[entry.path.split('.').at(-1)]
		});
		if (error) {
			// A retry can encounter a previously restored object. Keep it only if its bytes match.
			const existing = await readObject(storage, entry.path);
			if (digest(existing) !== entry.sha256) throw new Error('The destination already contains different photo bytes.');
		} else uploaded++;
		const restored = await readObject(storage, entry.path);
		if (digest(restored) !== entry.sha256) throw new Error('A restored photo does not match its backup.');
	}
	return { state: 'restore_verified', objects: manifest.objects.length, uploaded };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const [command, directory] = process.argv.slice(2);
	if (!directory || !['backup', 'verify', 'restore'].includes(command)) {
		console.log('Usage: node scripts/recovery-media.mjs backup|verify|restore <archive-directory>');
		process.exitCode = command ? 1 : 0;
	} else {
		try {
			console.log(JSON.stringify(await runMediaRecovery(command, directory, process.env)));
		} catch (failure) {
			console.error(failure instanceof Error ? failure.message : 'Media recovery could not be completed.');
			process.exitCode = 1;
		}
	}
}
