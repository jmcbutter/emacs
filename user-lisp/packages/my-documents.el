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

;;; Code:

(require 'subr-x)

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

(provide 'my-documents)
;;; my-documents.el ends here
