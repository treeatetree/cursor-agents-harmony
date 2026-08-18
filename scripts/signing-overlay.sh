# Shared local signing overlay. Source from build.sh / test.sh — do not execute.
# Copies gitignored build-profile.local.json5 over the tracked empty profile, then
# restores the tracked file on EXIT so secrets never stay in the working tree.

apply_signing_overlay() {
  SIGNING_OVERLAY_APPLIED=0
  if [[ -f "$ROOT/build-profile.local.json5" ]]; then
    echo "==> using gitignored build-profile.local.json5"
    cp "$ROOT/build-profile.json5" "$ROOT/build-profile.json5.committed"
    cp "$ROOT/build-profile.local.json5" "$ROOT/build-profile.json5"
    SIGNING_OVERLAY_APPLIED=1
  fi
}

restore_signing_overlay() {
  if [[ "${SIGNING_OVERLAY_APPLIED:-0}" == 1 && -f "$ROOT/build-profile.json5.committed" ]]; then
    mv -f "$ROOT/build-profile.json5.committed" "$ROOT/build-profile.json5"
    SIGNING_OVERLAY_APPLIED=0
  fi
}
