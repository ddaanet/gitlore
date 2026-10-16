import os
if 'GLMAP' not in globals():
  GLMAP = {}
  with open(os.environ['GLMAPFILE'],'rb') as f:
    next(f)
    for l in f:
      o, n = l.split()
      GLMAP[o] = n
  GLLOG = open(os.environ['GLLOGFILE'], 'ab')
  GLPATH = os.environ['GLPATH'].encode()
for ch in commit.file_changes:
  if ch.type == b'M' and ch.mode == b'160000':
    old = ch.blob_id
    new = GLMAP.get(old)
    GLLOG.write(b'%s %s %s %s\n' % (commit.original_id, ch.filename, old, new if new else b'UNMAPPED'))
    GLLOG.flush()
    if ch.filename == GLPATH and new:
      ch.blob_id = new
