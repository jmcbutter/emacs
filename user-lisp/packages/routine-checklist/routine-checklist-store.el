;;; routine-checklist-store.el --- Sexp storage for routine checklists -*- lexical-binding: t -*-

;;; Commentary:

;; Plain-text, Dropbox-safe per-entity `.eld' persistence for
;; `routine-checklist'.  Templates and runs are stored one file per
;; entity under `routine-checklist-data-directory', read strictly via
;; `read' (with `read-eval' disabled), and saved atomically via a
;; hidden temp file in the target directory followed by `rename-file'.

;;; Code:

(require 'cl-lib)
(require 'parse-time)
(require 'pp)
(require 'seq)
(require 'subr-x)

(defconst routine-checklist-store-schema-version 1
  "Current on-disk `.eld' schema version for routine checklists.")

(defconst routine-checklist-store-file-header
  ";; -*- mode: lisp-data; coding: utf-8 -*-\n"
  "Header line written at the top of every routine checklist `.eld' file.")

(defvar routine-checklist-data-directory "~/Dropbox/My Documents/Checklists/"
  "Root directory where routine checklist templates and runs are stored.")

(defvar routine-checklist-store--id-counter 0
  "Monotonic counter folded into generated IDs to guarantee uniqueness.")

(defconst routine-checklist-store-valid-run-policies
  '(carry-over fresh-per-repetition concurrent)
  "Valid `:run-policy' values for a routine checklist template.")

(defconst routine-checklist-store-valid-visibilities
  '(nil dimmed hidden)
  "Valid `:default-not-due-visibility' values for a template.")

(defconst routine-checklist-store-valid-cadence-units
  '(hours days weeks months)
  "Valid `:unit' values for a template item cadence.")

(defconst routine-checklist-store-valid-cadence-boundaries
  '(calendar elapsed)
  "Valid `:boundary' values for a template item cadence.")

(defconst routine-checklist-store-valid-run-statuses
  '(active archived-complete archived-incomplete)
  "Valid `:status' values for a routine checklist run.")

(defconst routine-checklist-store-valid-item-states
  '(pending checked skipped)
  "Valid `:state' values for a routine checklist run item.")

(defun routine-checklist-store--plist-p (obj)
  "Return non-nil if OBJ is a proper property list."
  (and (proper-list-p obj)
       (zerop (% (length obj) 2))))

(defun routine-checklist-store--plist-put (plist prop val)
  "Return a copy of PLIST with PROP set to VAL, preserving other keys."
  (plist-put (copy-sequence plist) prop val))

(defun routine-checklist-store--root-dir ()
  "Return the expanded root directory for routine checklist data."
  (file-name-as-directory (expand-file-name routine-checklist-data-directory)))

(defun routine-checklist-store-templates-dir ()
  "Return the directory holding template `.eld' files."
  (expand-file-name "templates" (routine-checklist-store--root-dir)))

(defun routine-checklist-store-active-runs-dir ()
  "Return the directory holding active run `.eld' files."
  (expand-file-name "runs/active" (routine-checklist-store--root-dir)))

(defun routine-checklist-store-archive-runs-dir ()
  "Return the root directory holding archived run `.eld' files."
  (expand-file-name "runs/archive" (routine-checklist-store--root-dir)))

(defun routine-checklist-store-ensure-dirs ()
  "Ensure the checklist data subdirectories exist and return the root dir."
  (dolist (dir (list (routine-checklist-store-templates-dir)
                     (routine-checklist-store-active-runs-dir)
                     (routine-checklist-store-archive-runs-dir)))
    (make-directory dir t))
  (routine-checklist-store--root-dir))

(defun routine-checklist-store--validate-safe-id (id kind)
  "Validate ID as a safe single-segment identifier for KIND."
  (unless (and (stringp id)
               (not (string-empty-p id))
               (not (string-match-p "[/\\\\]" id))
               (not (string-search ".." id)))
    (error "Invalid routine checklist %s ID: %S" kind id))
  id)

(defun routine-checklist-store-template-path (template-id)
  "Return the `.eld' file path for TEMPLATE-ID."
  (routine-checklist-store--validate-safe-id template-id "template")
  (expand-file-name (concat template-id ".eld")
                    (routine-checklist-store-templates-dir)))

(defun routine-checklist-store-generate-id (&optional length)
  "Generate a random lowercase hex identifier of LENGTH chars (default 8)."
  (let* ((len (or length 8))
         (seed (format "%s-%s-%s-%d"
                       (float-time)
                       (emacs-pid)
                       (random)
                       (cl-incf routine-checklist-store--id-counter)))
         (hash (secure-hash 'sha256 seed)))
    (substring hash 0 (min len (length hash)))))

(defun routine-checklist-store-slugify (name &optional existing-ids)
  "Convert NAME into a filesystem-safe, collision-free template slug.
When EXISTING-IDS is non-nil, avoid collisions against it; otherwise
avoid collisions against existing `.eld' files in `templates/'."
  (let* ((raw (downcase (or name "")))
         (cleaned (replace-regexp-in-string "[^a-z0-9]+" "-" raw))
         (trimmed (replace-regexp-in-string "\\`-\\|-\\'" "" cleaned))
         (base (if (string-empty-p trimmed) "template" trimmed))
         (taken (or existing-ids
                    (let ((dir (routine-checklist-store-templates-dir)))
                      (when (file-directory-p dir)
                        (mapcar #'file-name-base
                                (seq-filter
                                 #'file-regular-p
                                 (directory-files dir t "\\`[^.].*\\.eld\\'")))))))
         (candidate base)
         (suffix 2))
    (while (member candidate taken)
      (setq candidate (format "%s-%d" base suffix)
            suffix (1+ suffix)))
    candidate))

(defun routine-checklist-store--validate-cadence (cadence)
  "Validate CADENCE specification, signaling an error if malformed."
  (when cadence
    (unless (routine-checklist-store--plist-p cadence)
      (error "Invalid cadence specification (expected plist or nil): %S" cadence))
    (let ((every (plist-get cadence :every))
          (unit (plist-get cadence :unit))
          (boundary (plist-get cadence :boundary)))
      (unless (and (integerp every) (> every 0))
        (error "Invalid cadence :every (expected positive integer): %S" every))
      (unless (memq unit routine-checklist-store-valid-cadence-units)
        (error "Invalid cadence :unit: %S" unit))
      (unless (memq boundary routine-checklist-store-valid-cadence-boundaries)
        (error "Invalid cadence :boundary: %S" boundary))))
  cadence)

(defun routine-checklist-store-make-item (title &optional cadence id last-completed)
  "Construct a new template item plist with TITLE.
Optional CADENCE, ID, and LAST-COMPLETED initialize those fields."
  (routine-checklist-store--validate-cadence cadence)
  (list :id (or id (routine-checklist-store-generate-id))
        :title title
        :cadence cadence
        :last-completed last-completed))

(defun routine-checklist-store-make-template
    (name &optional id run-policy visibility items)
  "Construct a new template plist named NAME.
Optional ID, RUN-POLICY, VISIBILITY, and ITEMS override defaults."
  (list :schema-version routine-checklist-store-schema-version
        :id (or id (routine-checklist-store-slugify name))
        :name name
        :run-policy (or run-policy 'carry-over)
        :default-not-due-visibility visibility
        :items (or items nil)))

(defun routine-checklist-store--read-file (path)
  "Read and validate a single sexp plist from `.eld' file at PATH."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path))
    (goto-char (point-min))
    (let ((data (dlet ((read-eval nil))
                  (read (current-buffer)))))
      (unless (routine-checklist-store--plist-p data)
        (error "Invalid routine checklist data in %s: expected plist" path))
      (unless (equal (plist-get data :schema-version)
                     routine-checklist-store-schema-version)
        (error "Unsupported schema version %S in %s (expected %S)"
               (plist-get data :schema-version)
               path
               routine-checklist-store-schema-version))
      data)))

(defun routine-checklist-store--atomic-write (path data)
  "Pretty-print DATA with a `lisp-data' header atomically to PATH."
  (let* ((dir (file-name-directory path))
         (tmp (expand-file-name
               (format ".%s.%s.tmp"
                       (file-name-nondirectory path)
                       (routine-checklist-store-generate-id))
               dir)))
    (make-directory dir t)
    (condition-case err
        (progn
          (with-temp-buffer
            (insert routine-checklist-store-file-header)
            (let ((print-length nil)
                  (print-level nil)
                  (print-quoted t))
              (pp data (current-buffer)))
            (unless (eq (char-before) ?\n)
              (insert "\n"))
            (let ((coding-system-for-write 'utf-8)
                  (create-lockfiles nil)
                  (make-backup-files nil))
              (write-region (point-min) (point-max) tmp nil 'silent)))
          (rename-file tmp path t)
          path)
      (error
       (when (file-exists-p tmp)
         (ignore-errors (delete-file tmp nil)))
       (signal (car err) (cdr err))))))

(defun routine-checklist-store-list-templates ()
  "Return all saved template plists, sorted ascending by `:name'."
  (let ((dir (routine-checklist-store-templates-dir)))
    (when (file-directory-p dir)
      (let* ((files (seq-filter
                     #'file-regular-p
                     (directory-files dir t "\\`[^.].*\\.eld\\'")))
             (templates (mapcar #'routine-checklist-store--read-file files)))
        (sort templates
              (lambda (a b)
                (string<
                 (downcase (or (plist-get a :name) (plist-get a :id) ""))
                 (downcase (or (plist-get b :name) (plist-get b :id) "")))))))))

(defun routine-checklist-store-load-template (template-id &optional noerror)
  "Load and return the template plist for TEMPLATE-ID.
When NOERROR is non-nil, return nil if the template file does not exist."
  (let ((path (routine-checklist-store-template-path template-id)))
    (if (file-exists-p path)
        (routine-checklist-store--read-file path)
      (unless noerror
        (error "Routine checklist template not found: %s" template-id)))))

(defun routine-checklist-store--validate-template (template)
  "Validate TEMPLATE plist structure and fields, signaling on invalid data."
  (unless (routine-checklist-store--plist-p template)
    (error "Invalid routine checklist template: expected plist"))
  (let ((version (plist-get template :schema-version))
        (id (plist-get template :id))
        (name (plist-get template :name))
        (policy (plist-get template :run-policy))
        (visibility (plist-get template :default-not-due-visibility))
        (items (plist-get template :items)))
    (when (and (plist-member template :schema-version)
               (not (equal version routine-checklist-store-schema-version)))
      (error "Unsupported template schema version: %S" version))
    (routine-checklist-store-template-path id)
    (unless (and (stringp name)
                 (not (string-empty-p (string-trim name))))
      (error "Invalid template :name: %S" name))
    (unless (memq policy routine-checklist-store-valid-run-policies)
      (error "Invalid template :run-policy: %S" policy))
    (unless (memq visibility routine-checklist-store-valid-visibilities)
      (error "Invalid template :default-not-due-visibility: %S" visibility))
    (unless (proper-list-p items)
      (error "Invalid template :items (expected list): %S" items))
    (dolist (item items)
      (unless (routine-checklist-store--plist-p item)
        (error "Invalid template item (expected plist): %S" item))
      (let ((item-id (plist-get item :id))
            (title (plist-get item :title)))
        (unless (and (stringp item-id) (not (string-empty-p item-id)))
          (error "Invalid template item :id: %S" item-id))
        (unless (stringp title)
          (error "Invalid template item :title: %S" title))
        (routine-checklist-store--validate-cadence (plist-get item :cadence))))))

(defun routine-checklist-store-save-template (template)
  "Validate and atomically save TEMPLATE plist to disk.
Preserves unknown plist keys for forward compatibility.  Return the
saved file path."
  (routine-checklist-store-ensure-dirs)
  (routine-checklist-store--validate-template template)
  (let* ((to-save (if (plist-member template :schema-version)
                      template
                    (routine-checklist-store--plist-put
                     template :schema-version
                     routine-checklist-store-schema-version)))
         (path (routine-checklist-store-template-path (plist-get to-save :id))))
    (routine-checklist-store--atomic-write path to-save)))

(defun routine-checklist-store-delete-template (template-id)
  "Delete the `.eld' file for TEMPLATE-ID.
Return non-nil if the file existed and was deleted, nil otherwise."
  (let ((path (routine-checklist-store-template-path template-id)))
    (when (file-exists-p path)
      (delete-file path nil)
      t)))

;;;; Run persistence and archive

(defun routine-checklist-store--validate-run-id (run-id)
  "Validate RUN-ID as a safe run filename identifier."
  (routine-checklist-store--validate-safe-id run-id "run"))

(defun routine-checklist-store-generate-run-id (template-id &optional time)
  "Generate a unique run ID for TEMPLATE-ID at TIME (default current time)."
  (routine-checklist-store--validate-safe-id template-id "template")
  (format "%s-%s-%s"
          (format-time-string "%Y%m%dT%H%M%S" time)
          template-id
          (routine-checklist-store-generate-id 4)))

(defun routine-checklist-store-active-run-path (run-id)
  "Return the active `.eld' path for RUN-ID."
  (routine-checklist-store--validate-run-id run-id)
  (expand-file-name (concat run-id ".eld")
                    (routine-checklist-store-active-runs-dir)))

(defun routine-checklist-store--archive-year (run)
  "Return the 4-digit archive year string for RUN."
  (let ((ts (or (plist-get run :closed-at)
                (plist-get run :started-at))))
    (if (and (stringp ts)
             (string-match "\\`\\([0-9]\\{4\\}\\)-" ts))
        (match-string 1 ts)
      (format-time-string "%Y"))))

(defun routine-checklist-store-archived-run-path (run-id year)
  "Return the archived `.eld' path for RUN-ID in YEAR."
  (routine-checklist-store--validate-run-id run-id)
  (unless (and (stringp year)
               (string-match-p "\\`[0-9]\\{4\\}\\'" year))
    (error "Invalid archive year: %S" year))
  (expand-file-name (concat run-id ".eld")
                    (expand-file-name year (routine-checklist-store-archive-runs-dir))))

(defun routine-checklist-store--timestamp-epoch (ts)
  "Parse ISO-8601 timestamp TS into epoch seconds, or 0.0 if absent."
  (if (and (stringp ts) (not (string-empty-p ts)))
      (condition-case nil
          (if-let* ((parsed (parse-iso8601-time-string ts)))
              (float-time parsed)
            0.0)
        (error 0.0))
    0.0))

(defun routine-checklist-store--validate-run (run)
  "Validate RUN plist structure and fields, signaling on invalid data."
  (unless (routine-checklist-store--plist-p run)
    (error "Invalid routine checklist run: expected plist"))
  (let ((version (plist-get run :schema-version))
        (id (plist-get run :id))
        (template-id (plist-get run :template-id))
        (template-name (plist-get run :template-name))
        (status (plist-get run :status))
        (started-at (plist-get run :started-at))
        (items (plist-get run :items)))
    (when (and (plist-member run :schema-version)
               (not (equal version routine-checklist-store-schema-version)))
      (error "Unsupported run schema version: %S" version))
    (routine-checklist-store--validate-run-id id)
    (unless (and (stringp template-id) (not (string-empty-p template-id)))
      (error "Invalid run :template-id: %S" template-id))
    (unless (and (stringp template-name)
                 (not (string-empty-p (string-trim template-name))))
      (error "Invalid run :template-name: %S" template-name))
    (unless (memq status routine-checklist-store-valid-run-statuses)
      (error "Invalid run :status: %S" status))
    (unless (and (stringp started-at) (not (string-empty-p started-at)))
      (error "Invalid run :started-at: %S" started-at))
    (unless (proper-list-p items)
      (error "Invalid run :items (expected list): %S" items))
    (dolist (item items)
      (unless (routine-checklist-store--plist-p item)
        (error "Invalid run item (expected plist): %S" item))
      (unless (stringp (plist-get item :title))
        (error "Invalid run item :title: %S" (plist-get item :title)))
      (unless (memq (plist-get item :state)
                    routine-checklist-store-valid-item-states)
        (error "Invalid run item :state: %S" (plist-get item :state))))))

(defun routine-checklist-store--ensure-schema-version (plist)
  "Ensure PLIST has `:schema-version' set without stripping unknown keys."
  (if (plist-member plist :schema-version)
      plist
    (routine-checklist-store--plist-put
     plist :schema-version routine-checklist-store-schema-version)))

(defun routine-checklist-store-save-run (run)
  "Validate and atomically save active RUN plist to `runs/active/'.
Preserves unknown plist keys for forward compatibility.  Return the
saved file path."
  (routine-checklist-store-ensure-dirs)
  (routine-checklist-store--validate-run run)
  (let* ((to-save (routine-checklist-store--ensure-schema-version run))
         (path (routine-checklist-store-active-run-path
                (plist-get to-save :id))))
    (routine-checklist-store--atomic-write path to-save)))

(defun routine-checklist-store-load-run (run-id &optional noerror)
  "Load and return the active run plist for RUN-ID.
When NOERROR is non-nil, return nil if the run file does not exist."
  (let ((path (routine-checklist-store-active-run-path run-id)))
    (if (file-exists-p path)
        (routine-checklist-store--read-file path)
      (unless noerror
        (error "Active routine checklist run not found: %s" run-id)))))

(defun routine-checklist-store--sort-runs-newest-first (runs key-fn)
  "Sort RUNS descending by the timestamp returned by KEY-FN, then `:id'."
  (sort runs
        (lambda (a b)
          (let ((ta (routine-checklist-store--timestamp-epoch (funcall key-fn a)))
                (tb (routine-checklist-store--timestamp-epoch (funcall key-fn b))))
            (if (/= ta tb)
                (> ta tb)
              (string> (or (plist-get a :id) "")
                       (or (plist-get b :id) "")))))))

(defun routine-checklist-store-list-active-runs (&optional template-id)
  "Return active run plists from `runs/active/', newest first.
Never scans `runs/archive/'.  When TEMPLATE-ID is non-nil, return only
runs for that template."
  (let ((dir (routine-checklist-store-active-runs-dir)))
    (when (file-directory-p dir)
      (let* ((files (seq-filter
                     #'file-regular-p
                     (directory-files dir t "\\`[^.].*\\.eld\\'")))
             (runs (mapcar #'routine-checklist-store--read-file files))
             (filtered (if template-id
                           (seq-filter
                            (lambda (r)
                              (equal (plist-get r :template-id) template-id))
                            runs)
                         runs)))
        (routine-checklist-store--sort-runs-newest-first
         filtered (lambda (r) (plist-get r :started-at)))))))

(defun routine-checklist-store-archive-run (run)
  "Move finished RUN atomically into `runs/archive/<YYYY>/'.
Writes the archive file first, and deletes the active file only after
the write succeeds.  Return the archived file path."
  (routine-checklist-store--validate-run run)
  (unless (memq (plist-get run :status)
                '(archived-complete archived-incomplete))
    (error "Cannot archive run with status %S" (plist-get run :status)))
  (routine-checklist-store-ensure-dirs)
  (let* ((to-save (routine-checklist-store--ensure-schema-version run))
         (id (plist-get to-save :id))
         (year (routine-checklist-store--archive-year to-save))
         (archive-path (routine-checklist-store-archived-run-path id year))
         (active-path (routine-checklist-store-active-run-path id)))
    (routine-checklist-store--atomic-write archive-path to-save)
    (when (file-exists-p active-path)
      (delete-file active-path nil))
    archive-path))

(defun routine-checklist-store--archive-files ()
  "Return all non-hidden `.eld' file paths under `runs/archive/'."
  (let ((dir (routine-checklist-store-archive-runs-dir)))
    (when (file-directory-p dir)
      (seq-filter
       (lambda (f)
         (and (file-regular-p f)
              (string-match-p "\\`[^.].*\\.eld\\'"
                              (file-name-nondirectory f))))
       (directory-files-recursively
        dir "\\`[^.]" nil
        (lambda (sub)
          (not (string-prefix-p "." (file-name-nondirectory sub)))))))))

(defun routine-checklist-store-list-archived-runs (&optional template-id)
  "Return archived run plists, sorted newest first by `:closed-at'.
When TEMPLATE-ID is non-nil, return only runs for that template."
  (when-let* ((files (routine-checklist-store--archive-files)))
    (let* ((runs (mapcar #'routine-checklist-store--read-file files))
           (filtered (if template-id
                         (seq-filter
                          (lambda (r)
                            (equal (plist-get r :template-id) template-id))
                          runs)
                       runs)))
      (routine-checklist-store--sort-runs-newest-first
       filtered
       (lambda (r)
         (or (plist-get r :closed-at)
             (plist-get r :started-at)))))))

(defun routine-checklist-store-load-archived-run (id-or-path &optional noerror)
  "Load and return an archived run by run ID or file path ID-OR-PATH.
When NOERROR is non-nil, return nil if not found."
  (let ((path (if (and (stringp id-or-path)
                       (file-regular-p id-or-path))
                  id-or-path
                (routine-checklist-store--validate-run-id id-or-path)
                (seq-find
                 (lambda (f)
                   (equal (file-name-base f) id-or-path))
                 (routine-checklist-store--archive-files)))))
    (if path
        (routine-checklist-store--read-file path)
      (unless noerror
        (error "Archived routine checklist run not found: %s" id-or-path)))))

(provide 'routine-checklist-store)
;;; routine-checklist-store.el ends here
