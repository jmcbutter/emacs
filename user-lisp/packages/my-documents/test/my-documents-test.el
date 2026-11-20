;;; my-documents-test.el --- Tests for my-documents -*- lexical-binding: t -*-
;;; Code:
(eval-and-compile
  (add-to-list 'load-path
               (expand-file-name ".."
                                 (file-name-directory
                                  (or load-file-name
                                      (and (boundp 'byte-compile-current-file)
                                           byte-compile-current-file)
                                      buffer-file-name)))))
(require 'ert)
(require 'cl-lib)
(require 'my-documents)

(defmacro my-documents-test--with-root (&rest body)
  "Run BODY with a temporary `JMB/MY-DOCUMENTS-DIRECTORY'."
  `(let ((JMB/MY-DOCUMENTS-DIRECTORY (file-name-as-directory (make-temp-file "mydocs" t))))
     (unwind-protect (progn ,@body)
       (delete-directory JMB/MY-DOCUMENTS-DIRECTORY t))))

(ert-deftest my-documents-project ()
  (my-documents-test--with-root
   (should (= 2 (length (jmb/my-documents-create 'project "Foo"))))
   (should (file-directory-p (expand-file-name "Files/PROJECT - Foo/00 - Specs and Reqs" JMB/MY-DOCUMENTS-DIRECTORY)))
   (should (file-exists-p (expand-file-name "Planning/PROJECT - Foo.org" JMB/MY-DOCUMENTS-DIRECTORY)))
   (should-not (file-exists-p (expand-file-name "Roadmaps/Foo.org" JMB/MY-DOCUMENTS-DIRECTORY)))))

(ert-deftest my-documents-area ()
  (my-documents-test--with-root
   (should (= 3 (length (jmb/my-documents-create 'area " Bar "))))
   (should (file-directory-p (expand-file-name "Files/AREA - Bar/00 - Specs and Reqs" JMB/MY-DOCUMENTS-DIRECTORY)))
   (should (file-exists-p (expand-file-name "Planning/AREA - Bar.org" JMB/MY-DOCUMENTS-DIRECTORY)))
   (should (file-exists-p (expand-file-name "Roadmaps/Bar.org" JMB/MY-DOCUMENTS-DIRECTORY)))))

(ert-deftest my-documents-no-overwrite-and-labels ()
  (my-documents-test--with-root
   (let ((plan (expand-file-name "Planning/AREA - Baz.org" JMB/MY-DOCUMENTS-DIRECTORY)))
     (make-directory (file-name-directory plan) t)
     (with-temp-file plan (insert "keep"))
     (should (equal (list (expand-file-name "Roadmaps/Baz.org" JMB/MY-DOCUMENTS-DIRECTORY))
                    (jmb/my-documents-create 'area "Baz" '("Planning" "Roadmaps"))))
     (should (equal "keep" (with-temp-buffer (insert-file-contents plan) (buffer-string))))
     (should-not (file-exists-p (expand-file-name "Files/AREA - Baz" JMB/MY-DOCUMENTS-DIRECTORY))))))

;;;; Spec documents

(defun my-documents-test--write (path text)
  "Write TEXT to PATH, creating its folder."
  (make-directory (file-name-directory path) t)
  (with-temp-file path (insert text)))

(defun my-documents-test--read (file)
  "Return FILE's contents."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro my-documents-test--with-container (&rest body)
  "Run BODY in a temporary root with fixture palettes and a project.
Binds `container', `specs' and `tpl' for BODY."
  `(my-documents-test--with-root
    (let* ((tpl (expand-file-name "Templates" JMB/MY-DOCUMENTS-DIRECTORY))
           (container (expand-file-name "Files/PROJECT - Foo" JMB/MY-DOCUMENTS-DIRECTORY))
           (specs (expand-file-name "00 - Specs and Reqs" container)))
      (ignore specs)
      (pcase-dolist (`(,file . ,text)
                     '(("Common/GANTT.puml" . "@startgantt\ntitle {{TITLE}}\n@endgantt\n")
                       ("Common/SWIMLANE.puml" . "' common\n@startuml\ntitle {{TITLE}}\n@enduml\n")
                       ("Software/SWIMLANE.puml" . "' software\n@startuml\ntitle {{TITLE}}\n@enduml\n")
                       ("Software/_C4 DEFS.puml" . "' defs for {{CONTAINER}}\n")
                       ("Software/C4-L1 CONTEXT.puml" . "@startuml\n!include _C4 DEFS.puml\ntitle C4 L1 System Context: {{TITLE}}\n@enduml\n")
                       ("Software/ADR-0000.org" . ":PROPERTIES:\n:ID:       {{ID}}\n:END:\n#+title: ADR-{{NUMBER}}: {{TITLE}}\nFor {{CONTAINER}} by {{OWNER}} on {{DATE}}.\n")
                       ("Software/SPEC-00.org" . "#+title: SPEC-{{NUMBER}}: {{TITLE}}\n\n* Slices\nLinks.\n\n* Open\n")
                       ("Software/SLICE-00.org" . "#+title: SLICE-{{NUMBER}}: {{TITLE}}\nSlice of {{PARENT}}.\n")
                       ("Software/BRD.org" . "#+title: BRD: {{TITLE}}\n")
                       ("Life/BOM.org" . "#+title: BOM: {{TITLE}}\n")
                       ("README.org" . "not a palette\n")))
        (my-documents-test--write (expand-file-name file tpl) text))
      (jmb/my-documents-create 'project "Foo")
      ,@body)))

(defvar container-for-test nil
  "The project folder `my-documents-test--create' writes into.")

(defun my-documents-test--create (palette name title &optional parent)
  "Create a doc from PALETTE's template NAME with TITLE and PARENT."
  (jmb/spec-doc-create container-for-test
                       (cdr (assoc name (jmb/spec-doc-templates palette)))
                       title parent))

(ert-deftest my-documents-spec-doc-palettes-and-overrides ()
  (my-documents-test--with-container
   (should (equal '("Life" "Software") (jmb/spec-doc-palettes)))
   (let ((sw (jmb/spec-doc-templates "Software")))
     (should (equal '("ADR-0000" "BRD" "C4-L1 CONTEXT" "GANTT" "SLICE-00" "SPEC-00" "SWIMLANE")
                    (mapcar #'car sw)))
     (should (string-match-p "/Software/SWIMLANE" (cdr (assoc "SWIMLANE" sw)))))
   (should (string-match-p "/Common/SWIMLANE"
                           (cdr (assoc "SWIMLANE" (jmb/spec-doc-templates "Life")))))))

(ert-deftest my-documents-spec-doc-names-numbers-and-placeholders ()
  (my-documents-test--with-container
   (let ((container-for-test container))
     (should (equal "BRD - Reporting.org"
                    (file-name-nondirectory (my-documents-test--create "Software" "BRD" "Reporting"))))
     (should (equal "GANTT - Plan.puml"
                    (file-name-nondirectory (my-documents-test--create "Life" "GANTT" "Plan"))))
     (should (equal "ADR-0001 - Use QBO.org"
                    (file-name-nondirectory (my-documents-test--create "Software" "ADR-0000" "Use QBO"))))
     (let ((adr (my-documents-test--create "Software" "ADR-0000" " A/B ")))
       (should (equal "ADR-0002 - A-B.org" (file-name-nondirectory adr)))
       (let ((text (my-documents-test--read adr)))
         (should-not (string-match-p "{{" text))
         (should (string-match-p "^#\\+title: ADR-0002: A/B$" text))
         (should (string-match-p "For PROJECT - Foo" text))
         (should (string-match-p "^:ID: +[0-9a-f-]\\{36\\}$" text))))
     (should-error (my-documents-test--create "Software" "BRD" "Reporting") :type 'user-error)
     (should-error (my-documents-test--create "Software" "BRD" "  ") :type 'user-error))))

(ert-deftest my-documents-spec-doc-support-files ()
  (my-documents-test--with-container
   (let ((container-for-test container)
         (defs (expand-file-name "_C4 DEFS.puml" specs)))
     (my-documents-test--create "Software" "BRD" "No defs")
     (should-not (file-exists-p defs))
     (should (equal "C4-L1 CONTEXT - CRM.puml"
                    (file-name-nondirectory (my-documents-test--create "Software" "C4-L1 CONTEXT" "CRM"))))
     (should (equal "' defs for PROJECT - Foo\n" (my-documents-test--read defs)))
     (my-documents-test--write defs "edited\n")
     (my-documents-test--create "Software" "C4-L1 CONTEXT" "Other")
     (should (equal "edited\n" (my-documents-test--read defs))))))

(ert-deftest my-documents-spec-doc-slice-links-both-ways ()
  (my-documents-test--with-container
   (let* ((container-for-test container)
          (spec (my-documents-test--create "Software" "SPEC-00" "Matching"))
          (slice (my-documents-test--create "Software" "SLICE-00" "Shadow table"
                                            (file-name-nondirectory spec))))
     (should (equal '("SPEC-01 - Matching.org") (jmb/spec-doc--specs specs)))
     (should (equal "SLICE-01 - Shadow table.org" (file-name-nondirectory slice)))
     (should (string-match-p "Slice of \\[\\[file:SPEC-01 - Matching.org\\]\\[SPEC-01: Matching\\]\\]"
                             (my-documents-test--read slice)))
     (should (string-match-p
              "^\\* Slices\nLinks.\n- \\[\\[file:SLICE-01 - Shadow table.org\\]\\[SLICE-01: Shadow table\\]\\]\n\n\\* Open"
              (my-documents-test--read spec))))))

(ert-deftest my-documents-spec-doc-current-container ()
  (my-documents-test--with-container
   (let ((default-directory (file-name-as-directory specs)))
     (should (equal container (jmb/my-documents--current-container))))))

(ert-deftest my-documents-spec-doc-files-newest-first ()
  (my-documents-test--with-container
   (let ((container-for-test container))
     (let ((old (my-documents-test--create "Software" "BRD" "Old"))
           (new (my-documents-test--create "Software" "SWIMLANE" "New")))
       (set-file-times old (time-subtract nil 100))
       (my-documents-test--write (expand-file-name "SWIMLANE - New.png" specs) "")
       (my-documents-test--write (expand-file-name "BRD - Old.org~" specs) "")
       (should (equal (list new old) (jmb/spec-doc-files container)))))))

(ert-deftest my-documents-spec-doc-real-templates ()
  "Every live template has a description and fills all its placeholders."
  (let* ((JMB/MY-DOCUMENTS-DIRECTORY (expand-file-name "~/Dropbox/My Documents/"))
         (templates (mapcan #'jmb/spec-doc-templates (jmb/spec-doc-palettes))))
    (skip-unless templates)
    (my-documents-test--with-root
     (let ((container (expand-file-name "Files/PROJECT - Foo" JMB/MY-DOCUMENTS-DIRECTORY))
           (n 0))
       (pcase-dolist (`(,name . ,path) templates)
         (should (jmb/spec-doc-description path))
         (let ((text (my-documents-test--read
                      (jmb/spec-doc-create container path
                                           (format "%s %d" name (cl-incf n))))))
           (should-not (string-match-p "{{" text))
           (should-not (string-match-p jmb/spec-doc--description-regexp text))))))))

(provide 'my-documents-test)
;;; my-documents-test.el ends here
