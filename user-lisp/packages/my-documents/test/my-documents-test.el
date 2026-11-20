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

(defconst my-documents-test--real-templates
  (expand-file-name "~/Dropbox/My Documents/Templates/")
  "The live templates, copied into each test's temporary root.")

(defmacro my-documents-test--with-container (&rest body)
  "Run BODY in a temporary root with templates and a project folder.
Binds `container' and `specs' for BODY."
  `(my-documents-test--with-root
    (copy-directory my-documents-test--real-templates
                    (expand-file-name "Templates" JMB/MY-DOCUMENTS-DIRECTORY)
                    nil t t)
    (jmb/my-documents-create 'project "Foo")
    (let* ((container (expand-file-name "Files/PROJECT - Foo" JMB/MY-DOCUMENTS-DIRECTORY))
           (specs (expand-file-name "00 - Specs and Reqs" container)))
      (ignore specs)
      ,@body)))

(defun my-documents-test--read (file)
  "Return FILE's contents."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest my-documents-spec-doc-every-type-fills-placeholders ()
  (my-documents-test--with-container
   (dolist (type (mapcar #'car JMB/SPEC-DOC-TYPES))
     (let ((text (my-documents-test--read
                  (jmb/spec-doc-create container type "My Doc"))))
       (should-not (string-match-p "{{" text))
       (should (string-match-p "PROJECT - Foo" text))
       (when (string-suffix-p ".org" (nth 1 (assoc type JMB/SPEC-DOC-TYPES)))
         (should (string-match-p "^:ID: +[0-9a-f-]\\{36\\}$" text)))))))

(ert-deftest my-documents-spec-doc-diagram ()
  (my-documents-test--with-container
   (let ((path (jmb/spec-doc-create container "Sequence diagram" "Checkout")))
     (should (equal "SEQUENCE - Checkout.puml" (file-name-nondirectory path)))
     (should (string-match-p "^title Checkout$" (my-documents-test--read path))))))

(ert-deftest my-documents-spec-doc-names-and-numbers ()
  (my-documents-test--with-container
   (should (equal "BRD - Reporting.org"
                  (file-name-nondirectory
                   (jmb/spec-doc-create container "BRD" "Reporting"))))
   (should (equal "ADR-0001 - Use QBO.org"
                  (file-name-nondirectory
                   (jmb/spec-doc-create container "ADR" "Use QBO"))))
   (should (equal "ADR-0002 - A-B.org"
                  (file-name-nondirectory
                   (jmb/spec-doc-create container "ADR" " A/B "))))
   (should (string-match-p "^#\\+title: ADR-0002: A/B$"
                           (my-documents-test--read
                            (expand-file-name "ADR-0002 - A-B.org" specs))))
   (should-error (jmb/spec-doc-create container "BRD" "Reporting") :type 'user-error)
   (should-error (jmb/spec-doc-create container "BRD" "  ") :type 'user-error)))

(ert-deftest my-documents-spec-doc-slice-links-both-ways ()
  (my-documents-test--with-container
   (let* ((spec (jmb/spec-doc-create container "Spec" "Matching"))
          (slice (jmb/spec-doc-create container "Slice" "Shadow table"
                                      (file-name-nondirectory spec)))
          (spec-text (my-documents-test--read spec)))
     (should (equal "SLICE-01 - Shadow table.org" (file-name-nondirectory slice)))
     (should (string-match-p "\\[\\[file:SPEC-01 - Matching.org\\]\\[SPEC-01: Matching\\]\\]"
                             (my-documents-test--read slice)))
     (should (string-match-p
              "^\\* Slices\n\\(?:.*\n\\)*?- \\[\\[file:SLICE-01 - Shadow table.org\\]\\[SLICE-01: Shadow table\\]\\]\n\n\\* Open"
              spec-text)))))

(ert-deftest my-documents-spec-doc-current-container ()
  (my-documents-test--with-container
   (let ((default-directory (file-name-as-directory specs)))
     (should (equal container (jmb/my-documents--current-container))))))

(provide 'my-documents-test)
;;; my-documents-test.el ends here
