// sync_all.js
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { syncGroup } from './sync_upload.js'; // we’ll refactor sync_upload.js

// ——— Refactor sync_upload.js slightly so it exports this:
/// In sync_upload.js add at bottom:
/// export async function syncGroup(groupId, localDir, uploaderUid, uploaderName, serverBase) { … }

async function main() {
  const __dirname = path.dirname(fileURLToPath(import.meta.url));
  const uploadsDir = path.join(__dirname, 'uploads');

  // read command-line args or default
  const [
    , ,
    uploaderUid  = 'SYSTEM',
    uploaderName = 'Admin',
    serverBase   = 'http://localhost:3000'
  ] = process.argv;

  // list all group-subfolders under uploads/
  const groupIds = fs.readdirSync(uploadsDir)
    .filter(f => fs.statSync(path.join(uploadsDir, f)).isDirectory());

  for (const groupId of groupIds) {
    const localDir = path.join(uploadsDir, groupId);
    console.log(`\n🔄 Syncing group ${groupId}…`);
    await syncGroup(groupId, localDir, uploaderUid, uploaderName, serverBase);
  }

  console.log('\n🎉 Done syncing all groups.');
}

main().catch(err => {
  console.error('❌ sync_all.js error:', err);
  process.exit(1);
});
