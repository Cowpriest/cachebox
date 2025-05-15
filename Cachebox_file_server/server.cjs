// server.cjs

const express    = require('express');
const multer     = require('multer');
const cors       = require('cors');
const fs         = require('fs');
const path       = require('path');
const mime       = require('mime-types');
const { v4: uuid } = require('uuid');

const admin      = require('firebase-admin');
admin.initializeApp();
const firestore  = admin.firestore();
const { Timestamp, FieldValue } = admin.firestore;

const app        = express();
const port       = 3000;
const UPLOAD_DIR = path.join(__dirname, 'uploads');

app.use(cors());
app.use(express.json());

// ─── Helper to ensure per‐group folder + metadata.json
function ensureGroupDir(groupId) {
  const dir = path.join(UPLOAD_DIR, groupId);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const metaFile = path.join(dir, 'metadata.json');
  if (!fs.existsSync(metaFile)) fs.writeFileSync(metaFile, '[]');
  return { dir, metaFile };
}
function loadMetadata(groupId) {
  const { metaFile } = ensureGroupDir(groupId);
  const raw = fs.readFileSync(metaFile, 'utf8');
  try { return JSON.parse(raw); } catch { return []; }
}
function saveMetadata(groupId, arr) {
  const { metaFile } = ensureGroupDir(groupId);
  fs.writeFileSync(metaFile, JSON.stringify(arr, null, 2));
}

async function verifyFirebaseToken(req, res, next) {
  const auth = req.headers.authorization || '';
  if (!auth.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing Bearer token' });
  }
  const idToken = auth.split('Bearer ')[1];
  try {
    req.user = await admin.auth().verifyIdToken(idToken);
    // req.user now contains { uid, name?: string, email?: string, ... }
    return next();
  } catch (err) {
    console.error('❌ Token verification failed', err);
    return res.status(401).json({ error: 'Unauthorized: invalid token' });
  }
}
// Deletes a group document _and_ all of its subcollections.
async function deleteGroupAndSubcollections(groupId) {
  const docRef = firestore.collection('groups').doc(groupId);

  // 1) delete any subcollection docs
  const subcols = await docRef.listCollections();
  for (const col of subcols) {
    console.log(`🗑️ Deleting subcollection ${col.id} of group ${groupId}`);
    let snapshot;
    do {
      snapshot = await col.limit(100).get();
      if (snapshot.empty) break;
      const batch = firestore.batch();
      snapshot.docs.forEach(d => batch.delete(d.ref));
      await batch.commit();
    } while (!snapshot.empty);
  }

  // 2) delete the group document itself
  await docRef.delete();
  console.log(`✅ Deleted group doc ${groupId} and all its subcollections`);
}


// ─── MULTER for uploads ───────────────────────────────────────────

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const { dir } = ensureGroupDir(req.params.groupId);
    cb(null, dir);
  },
  filename: (req, file, cb) => cb(null, file.originalname)
});
const upload = multer({ storage });

// ─── Soft‐delete: schedule delete & boot‐out ───────────────────────
app.post('/group/:groupId/schedule-delete', async (req, res) => {
  const { groupId }       = req.params;
  const { requestingUid } = req.body;
  if (!requestingUid) {
    return res.status(400).json({ error: 'requestingUid required' });
  }

  const docRef = firestore.collection('groups').doc(groupId);
  const snap   = await docRef.get();
  if (!snap.exists) {
    return res.status(404).json({ error: 'Group not found' });
  }
  const data = snap.data();
  if (data.ownerUid !== requestingUid) {
    return res.status(403).json({ error: 'Only the owner may schedule deletion' });
  }

  // 1 minute from now (for testing; swap to 3 days in prod)
  const deletionDate = new Date(Date.now() + 60 * 1000);
  const deletionTs   = Timestamp.fromDate(deletionDate);
  await docRef.update({ deletionTimestamp: deletionTs });

  // How many milliseconds until we hit T+60s?
  const msUntilBootout = deletionDate.getTime() - Date.now();

  // ─── Schedule boot‐out exactly at 60s ──────────────────────────
  setTimeout(async () => {
    try {
      // Remove all members so clients get booted
      // (Assuming you store members in an array field `members`)
      await docRef.update({ members: [] });
      console.log(`🚪 Booted all members from ${groupId}`);
    } catch (e) {
      console.error(`❌ Bootout failed for ${groupId}:`, e);
    }
  }, msUntilBootout);

  // ─── Schedule full deletion ~65s (5s after boot‐out) ─────────
  setTimeout(async () => {
    try {
      // 1) Delete on‐disk folder
      const groupDir = path.join(UPLOAD_DIR, groupId);
      if (fs.existsSync(groupDir)) {
        fs.rmSync(groupDir, { recursive: true, force: true });
      }
      // 2) Delete Firestore doc + subcollections
      await deleteGroupAndSubcollections(groupId);
      console.log(`🔥 Fully deleted group ${groupId}`);
    } catch (e) {
      console.error(`❌ Deletion failed for ${groupId}:`, e);
    }
  }, msUntilBootout + 5000);

  return res.json({
    success:           true,
    deletionTimestamp: deletionTs.toDate(),
  });
});


// ─── Soft‐delete undo ─────────────────────────────────────────────
app.post('/group/:groupId/undo-delete', async (req, res) => {
  const { groupId }       = req.params;
  const { requestingUid } = req.body;
  if (!requestingUid) {
    return res.status(400).json({ error: 'requestingUid required' });
  }
  try {
    const docRef = firestore.collection('groups').doc(groupId);
    const snap   = await docRef.get();
    if (!snap.exists) {
      return res.status(404).json({ error: 'Group not found' });
    }
    const data = snap.data();
    if (data.ownerUid !== requestingUid) {
      return res.status(403).json({ error: 'Only the owner may undo deletion' });
    }
    await docRef.update({ deletionTimestamp: FieldValue.delete() });
    return res.json({ success: true });
  } catch (err) {
    console.error('❌ [/group/:groupId/undo-delete]', err);
    return res.status(500).json({ error: err.message });
  }
});

// ─── Serve uploaded files ────────────────────────────────────────
app.use('/files', express.static(UPLOAD_DIR, {
  setHeaders: (res, filePath) => {
    const ext = path.extname(filePath).toLowerCase();
    if (ext === '.mp3') res.setHeader('Content-Type', 'audio/mpeg');
    else if (ext === '.wav') res.setHeader('Content-Type', 'audio/wav');
    else if (ext === '.mp4') res.setHeader('Content-Type', 'video/mp4');
    else res.setHeader('Content-Type', mime.lookup(ext) || 'application/octet-stream');
  }
}));

// ─── Upload a file ───────────────────────────────────────────────
app.post(
  '/upload/:groupId',
  verifyFirebaseToken,          // ← guarantee req.user
  upload.single('file'),
  (req, res) => {
    const { groupId } = req.params;
    const fileName     = req.file.filename;
    const fileUrl      = `${req.protocol}://${req.get('host')}/files/${groupId}/${encodeURIComponent(fileName)}`;

    // now we know exactly who uploaded
    const uploadedByUid  = req.user.uid;
    const uploadedByName = req.user.name || req.user.email || req.user.uid;

    // build and save metadata exactly as before
    const { dir } = ensureGroupDir(groupId);
    const meta    = loadMetadata(groupId);
    const newRec  = {
      id:            uuid(),
      fileName,
      fileUrl,
      uploadedByUid,
      uploadedByName,
      storagePath:   `${groupId}/${fileName}`,
      uploadedAt:    new Date().toISOString(),
    };
    meta.push(newRec);
    saveMetadata(groupId, meta);

    return res.status(200).json(newRec);
  }
);


// ─── List files (with optional sync) ─────────────────────────────
app.get('/list/:groupId', (req, res) => {
  const { groupId } = req.params;
  const shouldSync  = req.query.sync === 'true';
  console.log(`🖥️ [list] ${groupId}, sync=${shouldSync}`);

  try {
    let meta = loadMetadata(groupId);

    if (shouldSync) {
      const { dir }     = ensureGroupDir(groupId);
      const actualFiles = fs.readdirSync(dir).filter(f => f !== 'metadata.json');
      let changed       = false;

      // add
      actualFiles.forEach(fn => {
        if (!meta.some(m => m.fileName === fn)) {
          meta.push({
            id:            uuid(),
            fileName:      fn,
            fileUrl:       `${req.protocol}://${req.get('host')}` +
                           `/files/${groupId}/${encodeURIComponent(fn)}`,
            uploadedByUid: 'SYSTEM',
            uploadedByName:'System',
            storagePath:   `${groupId}/${fn}`,
            uploadedAt:    new Date().toISOString(),
          });
          changed = true;
        }
      });
      // remove
      const before = meta.length;
      meta = meta.filter(m => actualFiles.includes(m.fileName));
      if (meta.length !== before) changed = true;

      if (changed) {
        saveMetadata(groupId, meta);
        console.log(`🖥️ [sync] updated metadata for ${groupId}`);
      }
    }

    meta.sort((a, b) => new Date(b.uploadedAt) - new Date(a.uploadedAt));
    res.json(meta);
  } catch (err) {
    console.error(`🛑 [list] error for ${groupId}:`, err.stack || err);
    res.status(500).json({ error: 'Server error: ' + err.message });
  }
});

// ─── Delete single file ──────────────────────────────────────────
app.delete('/delete/:groupId/:fileId', (req, res) => {
  const { groupId, fileId } = req.params;
  const { dir }             = ensureGroupDir(groupId);

  let meta = loadMetadata(groupId);
  const idx = meta.findIndex(m => m.id === fileId);
  if (idx === -1) {
    return res.status(404).json({ error: 'File metadata not found' });
  }
  const [ rec ] = meta.splice(idx, 1);
  const filePath = path.join(UPLOAD_DIR, rec.storagePath);
  if (fs.existsSync(filePath)) fs.unlinkSync(filePath);

  saveMetadata(groupId, meta);
  res.json({ success: true, id: fileId });
});

// ─── Purge fully‐expired groups every minute ──────────────────────
async function purgeExpiredGroups() {
  const now = Timestamp.now();
  try {
    const expired = await firestore
      .collection('groups')
      .where('deletionTimestamp', '<=', now)
      .get();

    for (const doc of expired.docs) {
      const groupId = doc.id;
      console.log(`🔥 Purging expired group ${groupId}`);

      // delete on‐disk folder
      const groupDir = path.join(UPLOAD_DIR, groupId);
      if (fs.existsSync(groupDir)) {
        try {
          fs.readdirSync(groupDir).forEach(file =>
            fs.unlinkSync(path.join(groupDir, file))
          );
          fs.rmdirSync(groupDir);
        } catch (err) {
          console.warn(`⚠️ Could not fully delete folder ${groupDir}:`, err);
        }
      }

      // remove Firestore doc
      await deleteGroupAndSubcollections(groupId);
    }
  } catch (err) {
    console.error('❌ purgeExpiredGroups error:', err);
  }
}
setInterval(purgeExpiredGroups, 60 * 1000);

// ─── Launch ───────────────────────────────────────────────────────
app.listen(port, () => {
  console.log(`✅ File server listening at http://localhost:${port}`);
});
