--mm:atomicArc
--threads:on
--d:useMalloc

when defined(release) or defined(danger):
  --opt:speed
  --passC:"-flto"
  --passL:"-flto"
  --passC:"-s"
  --passL:"-s"
