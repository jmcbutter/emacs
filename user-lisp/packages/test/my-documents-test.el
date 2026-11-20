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

(provide 'my-documents-test)
;;; my-documents-test.el ends here
