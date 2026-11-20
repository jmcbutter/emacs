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
;; `jmb/new-spec-doc' creates a document or PlantUML diagram in a
;; project or area's "00 - Specs and Reqs" folder from a template in a
;; palette folder under `JMB/MY-DOCUMENTS-DIRECTORY'/Templates/, such
;; as Software, Civil Engineering or Life.  Templates use {{ID}},
;; {{TITLE}}, {{DATE}}, {{OWNER}}, {{CONTAINER}}, {{NUMBER}} and
;; {{PARENT}} placeholders.  See "Specs and requirements documents"
;; below for how template names become file names.

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

;; Templates live in palette folders under Templates/, such as
;; Templates/Software/ or Templates/Life/, plus Templates/Common/ for
;; templates every palette offers.  A palette template overrides a
;; Common one with the same file name.
;;
;; A template's file name is the prefix of the files it creates:
;; SEQUENCE.puml creates "SEQUENCE - <Title>.puml".  A name ending in
;; "-" and zeros is numbered per folder with that many digits:
;; ADR-0000.org creates "ADR-0001 - <Title>.org".  Files starting with
;; "_" are support files: they are never offered, but are copied into
;; the folder when a new file's text mentions them.

(defconst JMB/COMMON-PALETTE "Common"
  "Template folder whose templates every palette offers.")

(defvar jmb/spec-doc--last-palette nil
  "The palette chosen last, offered as the default next time.")

(defun jmb/my-documents--templates-directory ()
  "Return the directory holding the palette template folders."
  (expand-file-name "Templates" JMB/MY-DOCUMENTS-DIRECTORY))

(defun jmb/spec-doc--hidden-p (name)
  "Return non-nil if file NAME is not a template to offer."
  (or (string-prefix-p "_" name)
      (string-prefix-p "." name)
      (string-suffix-p "~" name)))

(defun jmb/spec-doc-palettes ()
  "Return the names of the template palettes, without Common."
  (let ((dir (jmb/my-documents--templates-directory)))
    (and (file-directory-p dir)
         (seq-filter
          (lambda (name)
            (and (not (jmb/spec-doc--hidden-p name))
                 (not (equal name JMB/COMMON-PALETTE))
                 (file-directory-p (expand-file-name name dir))))
          (directory-files dir nil "\\`[^.]")))))

(defun jmb/spec-doc--palette-files (palette)
  "Return the regular files in PALETTE's template folder."
  (let ((dir (expand-file-name palette (jmb/my-documents--templates-directory))))
    (and (file-directory-p dir)
         (seq-filter #'file-regular-p (directory-files dir t "\\`[^.]")))))

(defun jmb/spec-doc-templates (palette)
  "Return an alist of (NAME . PATH) for the templates PALETTE offers.
NAME is the template's file name without its extension.  PALETTE's
own templates override Common templates with the same name."
  (let (result)
    (dolist (source (list JMB/COMMON-PALETTE palette))
      (dolist (path (jmb/spec-doc--palette-files source))
        (let ((name (file-name-base path)))
          (unless (jmb/spec-doc--hidden-p (file-name-nondirectory path))
            (setf (alist-get name result nil nil #'equal) path)))))
    (sort result (lambda (a b) (string< (car a) (car b))))))

(defun jmb/spec-doc--parse-name (name)
  "Split template NAME into (PREFIX . DIGITS).
DIGITS is nil unless NAME ends in \"-\" and zeros."
  (if (string-match "\\`\\(.+\\)-\\(0+\\)\\'" name)
      (cons (match-string 1 name) (length (match-string 2 name)))
    (cons name nil)))

(defun jmb/spec-doc--prefix-regexp (prefix)
  "Return a regexp matching numbered file names that start with PREFIX."
  (concat "\\`" (regexp-quote prefix) "-\\([0-9]+\\) - "))

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
       (directory-files dir nil (concat (jmb/spec-doc--prefix-regexp "SPEC")
                                        ".*\\.org\\'"))))

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

(defun jmb/spec-doc--label (file)
  "Return a link label such as \"SPEC-01: Title\" for FILE."
  (let ((base (file-name-base file)))
    (if (string-match "\\`\\(.+?\\) - \\(.*\\)\\'" base)
        (concat (match-string 1 base) ": " (match-string 2 base))
      base)))

(defun jmb/spec-doc--link (file)
  "Return an Org link to FILE, relative to its own folder."
  (format "[[file:%s][%s]]" (file-name-nondirectory file)
          (jmb/spec-doc--label file)))

(defconst jmb/spec-doc--description-regexp
  "^\\(?:#\\+\\|' \\)template:[ \t]*\\(.*\\)$"
  "Matches a template's description line.
In an Org template it is \"#+template: TEXT\" and in a PlantUML
template \"' template: TEXT\".  It says when to use the template, is
shown when choosing one, and is left out of the files it creates.")

(defun jmb/spec-doc-description (template)
  "Return the description line of TEMPLATE, or nil if it has none."
  (with-temp-buffer
    (insert-file-contents template nil 0 4096)
    (goto-char (point-min))
    (when (re-search-forward jmb/spec-doc--description-regexp nil t)
      (string-trim (match-string 1)))))

(defun jmb/spec-doc--fill (template values)
  "Return TEMPLATE text with each {{KEY}} replaced from VALUES.
VALUES is an alist of (KEY . STRING)."
  (with-temp-buffer
    (insert-file-contents template)
    (goto-char (point-min))
    (while (re-search-forward jmb/spec-doc--description-regexp nil t)
      (delete-region (match-beginning 0)
                     (min (point-max) (1+ (match-end 0)))))
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

(defun jmb/spec-doc--support-files (template)
  "Return the support files beside TEMPLATE or in Common.
Support files are those whose names start with \"_\"."
  (let ((dirs (list (file-name-directory template)
                    (expand-file-name JMB/COMMON-PALETTE
                                      (jmb/my-documents--templates-directory)))))
    (seq-filter #'file-regular-p
                (apply #'append
                       (mapcar (lambda (d)
                                 (and (file-directory-p d)
                                      (directory-files d t "\\`_")))
                               dirs)))))

(defun jmb/spec-doc--copy-support-files (template text dir values)
  "Copy into DIR the support files of TEMPLATE that TEXT mentions.
Fill their placeholders from VALUES.  Existing files are left alone."
  (dolist (support (jmb/spec-doc--support-files template))
    (let ((name (file-name-nondirectory support)))
      (when (and (string-search name text)
                 (not (file-exists-p (expand-file-name name dir))))
        (with-temp-file (expand-file-name name dir)
          (insert (jmb/spec-doc--fill support values)))))))

(defun jmb/spec-doc-create (container template title &optional parent)
  "Create a document titled TITLE in CONTAINER's specs folder from TEMPLATE.
CONTAINER is a project or area folder and TEMPLATE a template file.
PARENT, for a Slice, is the file name of its Spec in the same folder.
Return the new file's path."
  (let* ((title (string-trim title))
         (parsed (jmb/spec-doc--parse-name (file-name-base template)))
         (prefix (car parsed))
         (digits (cdr parsed))
         (dir (expand-file-name JMB/SPECS-AND-REQS-DIRECTORY-NAME container))
         (number (and digits (format (format "%%0%dd" digits)
                                     (jmb/spec-doc--next-number dir prefix))))
         (name (concat prefix (and number (concat "-" number)) " - "
                       (replace-regexp-in-string "[/\\\\:]" "-" title)
                       (file-name-extension template t)))
         (path (expand-file-name name dir))
         (parent-path (and parent (expand-file-name parent dir))))
    (when (string-empty-p title)
      (user-error "Title must not be empty"))
    (unless (file-regular-p template)
      (user-error "No template at %s" template))
    (when (file-exists-p path)
      (user-error "%s already exists" (abbreviate-file-name path)))
    (make-directory dir t)
    (let* ((values `(("ID" . ,(org-id-uuid))
                     ("TITLE" . ,title)
                     ("DATE" . ,(format-time-string "%Y-%m-%d"))
                     ("OWNER" . ,(or user-full-name ""))
                     ("CONTAINER" . ,(file-name-nondirectory
                                      (directory-file-name container)))
                     ("NUMBER" . ,(or number ""))
                     ("PARENT" . ,(if parent-path
                                      (jmb/spec-doc--link parent-path)
                                    "its spec"))))
           (text (jmb/spec-doc--fill template values)))
      (with-temp-file path (insert text))
      (jmb/spec-doc--copy-support-files
       template text dir (cons '("ID" . "") (cdr values))))
    (when parent-path
      (jmb/spec-doc--add-to-spec parent-path path))
    path))

(defun jmb/spec-doc--read-template (palette)
  "Ask for one of PALETTE's templates and return its path."
  (let* ((templates (jmb/spec-doc-templates palette))
         (width (apply #'max 0 (mapcar (lambda (c) (string-width (car c)))
                                       templates)))
         (annotate
          (lambda (name)
            (let ((path (cdr (assoc name templates))))
              (concat
               (make-string (- (1+ width) (string-width name)) ?\s)
               (format "%-8s %-17s %s"
                       (if (equal (file-name-extension path) "puml")
                           "diagram" "document")
                       (file-name-nondirectory
                        (directory-file-name (file-name-directory path)))
                       (or (jmb/spec-doc-description path) ""))))))
         (completion-extra-properties (list :annotation-function annotate)))
    (unless templates
      (user-error "No templates for palette %s" palette))
    (cdr (assoc (completing-read (format "%s template: " palette)
                                 templates nil t)
                templates))))

;;;###autoload
(defun jmb/new-spec-doc (container template title &optional parent)
  "Create a specs or requirements document or diagram and visit it.
Ask for the project or area CONTAINER, a palette, one of its
TEMPLATEs, the TITLE and, for a Slice, its PARENT Spec.  The file goes
in the container's \"00 - Specs and Reqs\" folder."
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
          (palette (completing-read "Palette: " (jmb/spec-doc-palettes)
                                    nil t nil nil jmb/spec-doc--last-palette))
          (template (progn (setq jmb/spec-doc--last-palette palette)
                           (jmb/spec-doc--read-template palette)))
          (prefix (car (jmb/spec-doc--parse-name (file-name-base template))))
          (title (read-string (format "%s title: " prefix)))
          (specs (and (equal prefix "SLICE")
                      (jmb/spec-doc--specs
                       (expand-file-name JMB/SPECS-AND-REQS-DIRECTORY-NAME
                                         container))))
          (parent (and specs
                       (let ((choice (completing-read
                                      "Spec (empty for none): " specs nil t)))
                         (unless (string-empty-p choice) choice)))))
     (list container template title parent)))
  (find-file (jmb/spec-doc-create container template title parent)))

(provide 'my-documents)
;;; my-documents.el ends here
