# Pinned model revisions

ReVox downloads the Whisper variants and their tokenizers at fixed Hugging Face commits (design spec §6.9), so the sizes shown on the Models screen, the per-file record and the installed check keep their meaning when the upstream repositories change. FluidAudio has no revision parameter, so the Silero VAD bundle and pocket-tts follow `main`; their per-file sizes are recorded at install time instead.

The values live in `ReVoxCore/Sources/ReVoxCore/ModelCatalog.swift` (`whisperRepoRevision` and the per-descriptor `tokenizerRevision`) and are locked by two tests: `ModelCatalogTests.testWhisperRevisionsArePinnedSHAs` (40 lowercase hex characters, never `main`) and `ModelCatalogTests.testWhisperRevisionsMatchRecordedListing` (exactly the commits in this table).

Listing date: 2026-09-02 (the date the byte sizes in `ModelCatalog` were read from the Hub).

| Repository | Used for | Commit |
|---|---|---|
| `argmaxinc/whisperkit-coreml` | tiny, base, small, medium, large-v3 (`openai_whisper-large-v3_947MB`) | `0f63a7800b00dd0226abd051b906c246e1907482` |
| `openai/whisper-tiny` | tokenizer files for tiny | `169d4a4341b33bc18d8881c4b69c2e104e1cc0af` |
| `openai/whisper-base` | tokenizer files for base | `e37978b90ca9030d5170a5c07aadb050351a65bb` |
| `openai/whisper-small` | tokenizer files for small | `973afd24965f72e36ca33b3055d56a652f456b4d` |
| `openai/whisper-medium` | tokenizer files for medium | `abdf7c39ab9d0397620ccaea8974cc764cd0953e` |
| `openai/whisper-large-v3` | tokenizer files for large-v3 | `06f233fe06e710322aca913c1bc4249a0d71fce1` |

To re-record (a catalog change: sizes and revision move together):

```bash
for r in argmaxinc/whisperkit-coreml openai/whisper-tiny openai/whisper-base openai/whisper-small openai/whisper-medium openai/whisper-large-v3; do
  printf '%s ' "$r"
  curl -sS "https://huggingface.co/api/models/$r?expand[]=sha" | python3 -c 'import sys,json; print(json.load(sys.stdin)["sha"])'
done
```

Then update, in one commit: the revisions in `ModelCatalog.swift`, the byte sizes from the new listing, `ModelCatalogTests.testWhisperRevisionsMatchRecordedListing`, `ModelCatalogTests.testFiveEntriesInOrderWithFolderNamesAndSizes`, and this table.
