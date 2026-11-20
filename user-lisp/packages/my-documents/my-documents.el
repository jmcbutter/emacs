;;; my-documents.el --- Scaffold projects and areas in My Documents -*- lexical-binding: t -*-

;;; Commentary:

;; Creates the folders and Org files a new project or area needs under
;; `JMB/MY-DOCUMENTS-DIRECTORY', following the layout in ~/AGENTS.md:
;;
;;   Project: Files/PROJECT - <Name>/00 - Specs and Reqs/
;;            Planning/PROJECT - <Name>.org
;;   Area:    Files/AREA - <Name>/00 - Specs and Reqs/
;;            Planning/AREA - <Name>.org
;;            Roadmaps/<Name>.org
;;
;; Existing files and folders are never overwritten.  With a prefix
;; argument, the commands ask which of the pieces to create.
;;
;; `jmb/new-spec-doc' creates a BRD, PRD, SRS, TDD, ADR, Spec, Slice or
;; PlantUML diagram in a project or area's "00 - Specs and Reqs" folder
;; from the Org and .puml templates in `JMB/MY-DOCUMENTS-DIRECTORY'/Templates/.  Templates use
;; {{ID}}, {{TITLE}}, {{DATE}}, {{OWNER}}, {{CONTAINER}}, {{NUMBER}} and
;; {{PARENT}} placeholders.

;;; Code:

(require 'subr-x)
(require 'seq)
(require 'org-id)

(defvar JMB/MY-DOCUMENTS-DIRECTORY (expand-file-name "~/Dropbox/My Documents/")
  "Root of the Dropbox document tree.")

(defvar JMB/SPECS-AND-REQS-DIRECTORY-NAME "00 - Specs and Reqs"
  "Folder created inside every new project or area's Files folder.")

(defvar JMB/PLANNING-FILE-HEADER
  (concat "#+TODO: TODO NEXT DOING PLANNING QUEUE STAGED REVIEWING WAITING"
          " | DONE SHIPPED COMPLETED CANCELED\n"
          "#+STARTUP: overview\n"
          "#+ARCHIVE: ./00_ARCHIVE/%s_archive::\n\n")
  "Initial contents of a new Planning file.")

(defvar JMB/ROADMAP-FILE-HEADER "#+TODO: TODO | DONE\n#+STARTUP: overview\n\n"
  "Initial contents of a new Roadmap file.")

(defun jmb/my-documents--prefix (kind)
  "Return the Files folder prefix for KIND, `project' or `area'."
  (pcase kind
    ('project "PROJECT - ")
    ('area "AREA - ")
    (_ (error "Unknown kind: %S" kind))))

(defun jmb/my-documents-pieces (kind name)
  "Return the pieces to create for a KIND named NAME.
Each piece is (LABEL TYPE PATH CONTENTS), where TYPE is `dir' or
`file'."
  (let* ((root JMB/MY-DOCUMENTS-DIRECTORY)
         (full (concat (jmb/my-documents--prefix kind) name))
         (files-dir (expand-file-name full (expand-file-name "Files" root))))
    (delq nil
          (list
           (list "Files" 'dir
                 (expand-file-name JMB/SPECS-AND-REQS-DIRECTORY-NAME files-dir)
                 nil)
           (list "Planning" 'file
                 (expand-file-name (concat full ".org")
                                   (expand-file-name "Planning" root))
                 JMB/PLANNING-FILE-HEADER)
           (when (eq kind 'area)
             (list "Roadmaps" 'file
                   (expand-file-name (concat name ".org")
                                     (expand-file-name "Roadmaps" root))
                   JMB/ROADMAP-FILE-HEADER))))))

(defun jmb/my-documents-create (kind name &optional labels)
  "Create the pieces for a KIND named NAME and return the paths created.
When LABELS is non-nil, create only pieces whose label is in it.
Paths that already exist are skipped."
  (when (string-empty-p (string-trim name))
    (user-error "Name must not be empty"))
  (let (created)
    (dolist (piece (jmb/my-documents-pieces kind (string-trim name)))
      (pcase-let ((`(,label ,type ,path ,contents) piece))
        (when (and (or (null labels) (member label labels))
                   (not (file-exists-p path)))
          (pcase type
            ('dir (make-directory path t))
            ('file
             (make-directory (file-name-directory path) t)
             (with-temp-file path (insert contents))))
          (push path created))))
    (nreverse created)))

(defun jmb/my-documents--read-labels (kind)
  "Ask which pieces to create for KIND."
  (let ((choices (if (eq kind 'area)
                     '("Files" "Planning" "Roadmaps")
                   '("Files" "Planning"))))
    (completing-read-multiple
     (format "Create (default %s): " (string-join choices ","))
     choices nil t nil nil (string-join choices ","))))

(defun jmb/my-documents--new (kind arg)
  "Interactively scaffold a KIND; ARG non-nil means choose the pieces."
  (let* ((name (read-string (format "New %s name: " kind)))
         (labels (and arg (jmb/my-documents--read-labels kind)))
         (created (jmb/my-documents-create kind name labels))
         (planning (nth 2 (assoc "Planning"
                                 (jmb/my-documents-pieces kind (string-trim name))))))
    (message (if created
                 (format "Created: %s" (mapconcat #'abbreviate-file-name created ", "))
               "Nothing to create; everything already exists"))
    (when (file-exists-p planning)
      (find-file planning))))

;;;###autoload
(defun jmb/new-project (arg)
  "Create a new project's Files folder and Planning file.
With prefix ARG, choose which pieces to create."
  (interactive "P")
  (jmb/my-documents--new 'project arg))

;;;###autoload
(defun jmb/new-area (arg)
  "Create a new area's Files folder, Planning file and Roadmap.
With prefix ARG, choose which pieces to create."
  (interactive "P")
  (jmb/my-documents--new 'area arg))

;;;; Specs and requirements documents

(defvar JMB/SPEC-DOC-TYPES
  '(("BRD" "BRD.org" "BRD" nil)
    ("PRD" "PRD.org" "PRD" nil)
    ("SRS" "SRS.org" "SRS" nil)
    ("TDD" "TDD.org" "TDD" nil)
    ("ADR" "ADR.org" "ADR" 4)
    ("Spec" "Spec.org" "SPEC" 2)
    ("Slice" "Slice.org" "SLICE" 2)
    ("C4 L1 Context diagram" "C4-L1 Context.puml" "C4-L1 CONTEXT" nil)
    ("C4 L2 Container diagram" "C4-L2 Container.puml" "C4-L2 CONTAINER" nil)
    ("C4 L3 Component diagram" "C4-L3 Component.puml" "C4-L3 COMPONENT" nil)
    ("Sequence diagram" "Sequence.puml" "SEQUENCE" nil)
    ("Activity diagram" "Activity.puml" "ACTIVITY" nil)
    ("State diagram" "State.puml" "STATE" nil)
    ("Data model" "Data Model.puml" "ERD" nil)
    ("Domain model" "Domain Model.puml" "DOMAIN" nil)
    ("Use case diagram" "Use Case.puml" "USECASE" nil)
    ("Deployment diagram" "Deployment.puml" "DEPLOYMENT" nil))
  "Document types for `jmb/new-spec-doc'.
Each entry is (TYPE TEMPLATE PREFIX DIGITS).  The new file takes the
template's extension, so .puml templates make PlantUML diagrams.  When
DIGITS is non-nil, documents of that type are numbered per folder with
that many digits.")

(defun jmb/my-documents--templates-directory ()
  "Return the directory holding the spec document templates."
  (expand-file-name "Templates" JMB/MY-DOCUMENTS-DIRECTORY))

(defun jmb/my-documents--containers ()
  "Return the project and area folders under Files/."
  (let ((files (expand-file-name "Files" JMB/MY-DOCUMENTS-DIRECTORY)))
    (when (file-directory-p files)
      (seq-filter #'file-directory-p
                  (directory-files files t "\\`\\(PROJECT\\|AREA\\) - ")))))

(defun jmb/my-documents--current-container ()
  "Return the project or area folder containing `default-directory', if any."
  (let ((dir (expand-file-name default-directory)))
    (seq-find (lambda (c) (string-prefix-p (file-name-as-directory c) dir))
              (jmb/my-documents--containers))))

(defun jmb/spec-doc--prefix-regexp (prefix)
  "Return a regexp matching numbered file names that start with PREFIX."
  (concat "\\`" (regexp-quote prefix) "-\\([0-9]+\\) - .*\\.org\\'"))

(defun jmb/spec-doc--next-number (dir prefix)
  "Return the next free number for PREFIX documents in DIR."
  (let ((rx (jmb/spec-doc--prefix-regexp prefix)))
    (1+ (apply #'max 0
               (mapcar (lambda (f)
                         (string-match rx f)
                         (string-to-number (match-string 1 f)))
                       (and (file-directory-p dir)
                            (directory-files dir nil rx)))))))

(defun jmb/spec-doc--specs (dir)
  "Return the Spec document file names in DIR."
  (and (file-directory-p dir)
       (directory-files dir nil (jmb/spec-doc--prefix-regexp "SPEC"))))

(defun jmb/spec-doc--label (file)
  "Return a link label such as \"SPEC-01: Title\" for FILE."
  (let ((base (file-name-base file)))
    (if (string-match "\\`\\([A-Z]+-[0-9]+\\) - \\(.*\\)\\'" base)
        (concat (match-string 1 base) ": " (match-string 2 base))
      base)))

(defun jmb/spec-doc--link (file)
  "Return an Org link to FILE, relative to its own folder."
  (format "[[file:%s][%s]]" (file-name-nondirectory file)
          (jmb/spec-doc--label file)))

(defun jmb/spec-doc--fill (template values)
  "Return TEMPLATE text with each {{KEY}} replaced from VALUES.
VALUES is an alist of (KEY . STRING)."
  (with-temp-buffer
    (insert-file-contents template)
    (dolist (pair values)
      (goto-char (point-min))
      (let ((token (format "{{%s}}" (car pair))))
        (while (search-forward token nil t)
          (replace-match (cdr pair) t t))))
    (buffer-string)))

(defun jmb/spec-doc--add-to-spec (spec-file slice-file)
  "Add a link to SLICE-FILE under the Slices heading of SPEC-FILE."
  (with-temp-buffer
    (insert-file-contents spec-file)
    (goto-char (point-min))
    (when (re-search-forward "^\\* Slices[ \t]*$" nil t)
      (goto-char (if (re-search-forward "^\\* " nil t)
                     (match-beginning 0)
                   (point-max)))
      (skip-chars-backward " \t\n")
      (end-of-line)
      (insert "\n- " (jmb/spec-doc--link slice-file))
      (write-region nil nil spec-file nil 'silent))))

(defun jmb/spec-doc-create (container type title &optional parent)
  "Create a TYPE document titled TITLE in CONTAINER's specs folder.
CONTAINER is a project or area folder.  PARENT, for a Slice, is the
file name of its Spec in the same folder.  Return the new file's path."
  (let* ((entry (or (assoc type JMB/SPEC-DOC-TYPES)
                    (user-error "Unknown document type: %s" type)))
         (title (string-trim title))
         (dir (expand-file-name JMB/SPECS-AND-REQS-DIRECTORY-NAME container))
         (template (expand-file-name (nth 1 entry)
                                     (jmb/my-documents--templates-directory)))
         (prefix (nth 2 entry))
         (digits (nth 3 entry))
         (number (and digits (format (format "%%0%dd" digits)
                                     (jmb/spec-doc--next-number dir prefix))))
         (name (concat prefix (and number (concat "-" number)) " - "
                       (replace-regexp-in-string "[/\\\\:]" "-" title)
                       (file-name-extension template t)))
         (path (expand-file-name name dir))
         (parent-path (and parent (expand-file-name parent dir))))
    (when (string-empty-p title)
      (user-error "Title must not be empty"))
    (unless (file-exists-p template)
      (user-error "No template at %s" template))
    (when (file-exists-p path)
      (user-error "%s already exists" (abbreviate-file-name path)))
    (make-directory dir t)
    (with-temp-file path
      (insert (jmb/spec-doc--fill
               template
               `(("ID" . ,(org-id-uuid))
                 ("TITLE" . ,title)
                 ("DATE" . ,(format-time-string "%Y-%m-%d"))
                 ("OWNER" . ,(or user-full-name ""))
                 ("CONTAINER" . ,(file-name-nondirectory
                                  (directory-file-name container)))
                 ("NUMBER" . ,(or number ""))
                 ("PARENT" . ,(if parent-path
                                  (jmb/spec-doc--link parent-path)
                                "its spec"))))))
    (when parent-path
      (jmb/spec-doc--add-to-spec parent-path path))
    path))

;;;###autoload
(defun jmb/new-spec-doc (container type title &optional parent)
  "Create a specs or requirements document or diagram and visit it.
Ask for the project or area CONTAINER, the document TYPE, its TITLE
and, for a Slice, its PARENT Spec.  The document goes in the
container's \"00 - Specs and Reqs\" folder."
  (interactive
   (let* ((containers (jmb/my-documents--containers))
          (current (jmb/my-documents--current-container))
          (container
           (expand-file-name
            (completing-read "Project or area: "
                             (mapcar #'file-name-nondirectory containers)
                             nil t nil nil
                             (and current (file-name-nondirectory current)))
            (expand-file-name "Files" JMB/MY-DOCUMENTS-DIRECTORY)))
          (type (completing-read "Document type: "
                                 (mapcar #'car JMB/SPEC-DOC-TYPES) nil t))
          (title (read-string (format "%s title: " type)))
          (specs (and (equal type "Slice")
                      (jmb/spec-doc--specs
                       (expand-file-name JMB/SPECS-AND-REQS-DIRECTORY-NAME
                                         container))))
          (parent (and specs
                       (let ((choice (completing-read
                                      "Spec (empty for none): " specs nil t)))
                         (unless (string-empty-p choice) choice)))))
     (list container type title parent)))
  (find-file (jmb/spec-doc-create container type title parent)))

(provide 'my-documents)
;;; my-documents.el ends here
