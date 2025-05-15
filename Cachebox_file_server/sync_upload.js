// sync_upload.js

import fs from 'fs';
import path from 'path';
import axios from 'axios';
import FormData from 'form-data';

/**
 * Usage:
 *   node sync_upload.js \
 *     <groupId> \
 *     <localUploadsDir> \
 *     <uploaderUid> \
 *     <uploaderName> \
 *     [serverBase]
 *
 * Example:
 *   node sync_upload.js \
 *     QfCgtADsi4VhkDUm92fk \
 *     ./uploads/QfCgtADsi4VhkDUm92fk \
 *     uid123 \
 *     Admin \
 *     http://cacheboxcapstone.duckdns.org:3000
 */
async function main() {
  const [
    , , groupId, localDir, uploaderUid, uploaderName,
    serverBase = 'http://localhost:3000'
  ] = process.argv;

  if (!groupId || !localDir || !uploaderUid || !uploaderName) {
    console.error('Usage: node sync_upload.js <groupId> <localDir> <uploaderUid> <uploaderName> [serverBase]');
    process.exit(1);
  }

  // 1) fetch existing metadata
  console.log(`⏳ Fetching existing metadata for group ${groupId}…`);
  const listRes = await axios.get(`${serverBase}/list/${groupId}`);
  const existingNames = listRes.data.map((f) => f.fileName);
  console.log(`Found ${existingNames.length} existing files.`);

  // 2) scan local folder
  const allFiles = fs.readdirSync(localDir).filter(f => f !== 'metadata.json');
  const toUpload = allFiles.filter(f => !existingNames.includes(f));
  console.log(`🔍 Found ${toUpload.length} new file(s) to upload.`);

  // 3) upload each via your POST /upload endpoint
  for (const fileName of toUpload) {
    const fullPath = path.join(localDir, fileName);
    console.log(`🚀 Uploading ${fileName}…`);

    const form = new FormData();
    form.append('file', fs.createReadStream(fullPath));
    form.append('uploadedByUid', uploaderUid);
    form.append('uploadedByName', uploaderName);

    const uploadRes = await axios.post(
      `${serverBase}/upload/${groupId}`,
      form,
      { headers: form.getHeaders() }
    );
    console.log(`✅ Uploaded:`, uploadRes.data);
  }

  console.log('🎉 All done!');
}

main().catch(err => {
  console.error('❌ Error during sync:', err);
  process.exit(1);
});
