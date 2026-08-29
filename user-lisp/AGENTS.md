# Emacs Lisp Package Instructions

## Isolated compilation

When creating or changing a package under this tree:

- Make test and support files find locally required source without relying on an
  interactive Emacs session. Before the first local `require`, add the source
  directory to `load-path` inside `eval-and-compile`. For a sibling source file,
  use:

  ```elisp
  (eval-and-compile
    (add-to-list
     'load-path
     (file-name-directory
      (or load-file-name
          (and (boundp 'byte-compile-current-file)
               byte-compile-current-file)
          buffer-file-name))))
  ```

- Initialize the repository's `elpa` directory before compiling code that has
  external package dependencies, and pass `-L` for every directory containing
  locally required source.
- Compile source and tests with warnings treated as errors, then run the focused
  ERT suite. The isolated commands must succeed without loading the user's init
  file.
