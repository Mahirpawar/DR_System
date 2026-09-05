# Code Standards — Why This Exists

The goal: **any function, opened in isolation, with no conversation history and no memory of prior sessions, should be fully understandable from its own header.** This matters especially if work resumes under a different model or after a long gap — the header is the contract, not anyone's memory of a conversation.

Every `.m` file in `src/` MUST start with this header block:

```matlab
% FUNCTION: <name>
% MODULE: <which of the 5 pipeline modules this belongs to>
% STATUS: <DONE_TESTED | IMPLEMENTED_UNTESTED | STUB>
%
% PURPOSE:
%   <1-3 sentences: what this function does and why it exists in the pipeline>
%
% INPUTS:
%   <name> (<type>) - <description, including valid range/format>
%
% OUTPUTS:
%   <name> (<type>) - <description>
%
% DEPENDS ON:
%   <other functions/files this calls, or "none">
%
% CALLED BY:
%   <which functions/scripts call this, or "not yet wired in">
%
% KEY ASSUMPTIONS:
%   <anything a future reader needs to know that isn't obvious from code alone>
%
% TODO (if STUB or IMPLEMENTED_UNTESTED):
%   <specific, concrete next steps — not "improve this" but "train U-Net on
%    DRIVE using X images, target Y IoU">
```

## Rules

1. **No orphan logic.** If a function does something non-obvious (a magic threshold, a specific filter size), comment *why* that value, not just *what* the line does.
2. **STATUS must be accurate.** Update it the moment a function's state changes — this is what `PROGRESS.md`'s file manifest is built from. A mismatch between a file's STATUS and `PROGRESS.md` is a bug.
3. **I/O contracts are load-bearing.** Other modules depend on exact input/output shapes and types. If you change a signature, grep the whole `src/` tree for callers and update them in the same session — don't leave a dangling contract change for "later."
4. **Stubs still run.** A STUB function should have a valid signature and return a plausible dummy output (not throw an error), so the rest of the pipeline can be test-run end-to-end even before every module is real. Use `warning('STUB: <function> not yet implemented')` inside stubs.
5. **Don't delete deprecated approaches silently.** If you replace an approach (e.g., rule-based IQA → CNN-based IQA), keep the old function renamed with `_v1` suffix if it's referenced anywhere in the validation/ablation plan (check `PROGRESS.md` Section 5 first).
