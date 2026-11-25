# autolisp-emacs

AutoLISP and DCL editing and debugging for Emacs 29.1 or later, covering the
features of Autodesk's [AutoLispExt](https://github.com/Autodesk-AutoCAD/AutoLispExt)
for VS Code.

## Setup

`user-lisp/lang/lang-autolisp.el` loads this package, and `init.el` requires that.

Debugging needs the `dape` package, which `lang-autolisp.el` installs.
Everything else has no dependencies. `.lsp` files open in `autolisp-mode` from then on,
including any that are really Common Lisp.

## Debugging

`C-c C-a` attaches to a running AutoCAD 2021 or later (not LT), asking which if there
are several. `M-x autolisp-debug-launch` starts one. Then use dape as usual
(`C-x C-a` prefix: `b` breakpoint, `n` next, `s` step in, `o` step out, `c` continue).

**Attaching loads, and so runs, the current file** in AutoCAD.

**While stopped at a breakpoint, or on an error, AutoCAD does not respond.** Continue or quit to
release it. `dape-quit` on an attached session disconnects and does not ask for AutoCAD
to be closed; a launched one may close with the session.

Within one session AutoCAD loads a file once. `C-c C-l` is refused for a file that is
already loaded, changed or not. After an edit, use `C-c C-k`, which disconnects,
attaches to the same AutoCAD and loads the file again, keeping breakpoints.

Do not evaluate `(load "...")` on a file outside AutoCAD's trusted folders: it can open
a security prompt in AutoCAD, which blocks the session until it is answered.

Results of `C-x C-e` and the like appear in `*dape-repl*` as output.

To launch Civil 3D, set `autolisp-launch-parameters` to the switches in its shortcut.

The adapter has no pause, conditional or data breakpoints, logpoints, or variable setting.

## Keys

| Key | Command |
|---|---|
| `C-c C-a` | Attach the debugger |
| `C-c C-l` | Load this file into AutoCAD (debug session needed) |
| `C-c C-k` | Reconnect and load this file again, after an edit |
| `C-x C-e`, `C-M-x`, `C-c C-e` | Evaluate expression, defun, region in AutoCAD |
| `M-.`, `M-?` | Definition, references |
| `C-c C-r` | Rename symbol |
| `C-h .` | Help for what is at point: built-in, your symbol, constant, error |
| `C-c C-d`, `C-c C-w` | Describe by name, open online help |
| `C-c C-;` | Insert doc comment |
| `C-c C-n`, `C-c C-f` | Insert, fold `;#region` |

Projects (`.prj`): `M-x autolisp-open-project`, `autolisp-create-project`,
`autolisp-add-to-project`, `autolisp-remove-from-project`, `autolisp-find-project-file`,
`autolisp-find-in-project`, `autolisp-replace-in-project`, `autolisp-save-project`.

## Differences from AutoLispExt

- No formatter. `indent-region` follows AutoLispExt's indentation rules but does not
  re-break lines.
- No project side panel; the commands above replace it.
- No snippets.
- Completion is ranked: your locals, then your other symbols, then built-ins by how
  often the LSP files AutoCAD ships use them. It matches inside words and fuzzily
  (`vlstr`), and offers an argument's values: variables in `getvar`, table names in
  `tblsearch`, tile keys and dialog names from nearby DCL files, enumerators, and
  ActiveX members.
- Commands complete only inside calls such as `command`. Set
  `autolisp-complete-commands-in` to `t` for every string.
- Renaming a symbol that is not `@Global` asks before touching other files, instead of
  silently leaving them.

## Tests

    emacs -Q --batch -L . -l test/autolisp-test.el -f ert-run-tests-batch-and-exit

Add dape and jsonrpc to the load path to include the debugger tests, which use
`test/fake-adapter.py` (needs Python) rather than AutoCAD.

## License

Apache-2.0. `data/usage.txt` holds counts made for this package. The rest of `data/` and
`test/fixtures/` are unmodified files from AutoLispExt; see
`data/LICENSE-AutoLispExt.md`.
