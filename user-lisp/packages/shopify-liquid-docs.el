;;; shopify-liquid-docs.el --- Browse Shopify Liquid documentation -*- lexical-binding: t -*-

;; Author: Jordan Butterfield
;; Version: 0.2.0
;; Package-Requires: ((emacs "28.1") (markdown-mode "2.6"))
;; Keywords: docs, shopify, liquid
;; URL: https://github.com/Shopify/theme-liquid-docs

;;; Commentary:
;;
;; Download and browse Shopify Liquid theme documentation from within Emacs.
;; Data is sourced from https://github.com/Shopify/theme-liquid-docs
;;
;; Main entry points:
;;   `shopify-liquid-docs-search'   - Search across all filters, objects, and tags
;;   `shopify-liquid-docs-filters'  - Browse filters
;;   `shopify-liquid-docs-objects'  - Browse objects
;;   `shopify-liquid-docs-tags'     - Browse tags
;;   `shopify-liquid-docs-lookup'   - Look up the symbol at point

;;; Code:

(require 'json)
(require 'url)
(require 'markdown-mode)

;;; --- Customization ---

(defgroup shopify-liquid-docs nil
  "Browse Shopify Liquid documentation."
  :group 'tools
  :prefix "shopify-liquid-docs-")

(defcustom shopify-liquid-docs-cache-dir
  (expand-file-name "shopify-liquid-docs" user-emacs-directory)
  "Directory to cache downloaded JSON files."
  :type 'directory)

(defcustom shopify-liquid-docs-base-url
  "https://raw.githubusercontent.com/Shopify/theme-liquid-docs/main/data/"
  "Base URL for the Shopify theme-liquid-docs JSON files."
  :type 'string)

(defcustom shopify-liquid-docs-data-files
  '("filters.json" "objects.json" "tags.json")
  "List of JSON data files to download."
  :type '(repeat string))

;;; --- Internal State ---

(defvar shopify-liquid-docs--filters nil "Parsed filter entries.")
(defvar shopify-liquid-docs--objects nil "Parsed object entries.")
(defvar shopify-liquid-docs--tags nil "Parsed tag entries.")
(defvar shopify-liquid-docs--loaded nil "Non-nil when data has been loaded.")

;;; --- Downloading & Caching ---

(defun shopify-liquid-docs--ensure-cache-dir ()
  "Create the cache directory if it doesn't exist."
  (unless (file-directory-p shopify-liquid-docs-cache-dir)
    (make-directory shopify-liquid-docs-cache-dir t)))

(defun shopify-liquid-docs--cache-path (filename)
  "Return the local cache path for FILENAME."
  (expand-file-name filename shopify-liquid-docs-cache-dir))

(defun shopify-liquid-docs--download-file (filename)
  "Download FILENAME from the remote repo into the cache directory."
  (shopify-liquid-docs--ensure-cache-dir)
  (let* ((url (concat shopify-liquid-docs-base-url filename))
         (dest (shopify-liquid-docs--cache-path filename)))
    (message "Downloading %s..." filename)
    (url-copy-file url dest t)
    (message "Downloaded %s." filename)
    dest))

(defun shopify-liquid-docs-download ()
  "Download all documentation JSON files to the cache directory."
  (interactive)
  (dolist (file shopify-liquid-docs-data-files)
    (shopify-liquid-docs--download-file file))
  (shopify-liquid-docs--load-data t)
  (message "Shopify Liquid docs downloaded and loaded."))

(defun shopify-liquid-docs--parse-json-file (filename)
  "Parse a cached JSON FILENAME and return the result."
  (let ((path (shopify-liquid-docs--cache-path filename)))
    (unless (file-exists-p path)
      (shopify-liquid-docs--download-file filename))
    (with-temp-buffer
      (insert-file-contents path)
      (json-parse-buffer :object-type 'alist :array-type 'list))))

(defun shopify-liquid-docs--load-data (&optional force)
  "Load cached JSON data into internal variables.
When FORCE is non-nil, reload even if already loaded."
  (when (or force (not shopify-liquid-docs--loaded))
    (setq shopify-liquid-docs--filters (shopify-liquid-docs--parse-json-file "filters.json")
          shopify-liquid-docs--objects (shopify-liquid-docs--parse-json-file "objects.json")
          shopify-liquid-docs--tags (shopify-liquid-docs--parse-json-file "tags.json")
          shopify-liquid-docs--loaded t)))

(defun shopify-liquid-docs--ensure-loaded ()
  "Ensure documentation data is loaded."
  (shopify-liquid-docs--load-data))

;;; --- Text Helpers ---

(defun shopify-liquid-docs--decode-entities (text)
  "Decode HTML entities in TEXT."
  (when text
    (let ((result text))
      (setq result (string-replace "&lt;" "<" result))
      (setq result (string-replace "&gt;" ">" result))
      (setq result (string-replace "&amp;" "&" result))
      (setq result (string-replace "&quot;" "\"" result))
      (setq result (string-replace "&#39;" "'" result))
      result)))

(defun shopify-liquid-docs--get (alist key)
  "Get KEY from ALIST, returning nil for empty strings.
HTML entities in string values are decoded."
  (let ((val (alist-get key alist)))
    (cond
     ((and (stringp val) (string-empty-p val)) nil)
     ((stringp val) (shopify-liquid-docs--decode-entities val))
     (t val))))

;;; --- Markdown Rendering ---

(defun shopify-liquid-docs--insert-heading (text level)
  "Insert TEXT as a markdown heading at LEVEL (1-3)."
  (insert (make-string level ?#) " " text "\n"))

(defun shopify-liquid-docs--insert-field (label value)
  "Insert a **LABEL:** VALUE line if VALUE is non-nil."
  (when value
    (insert "**" label ":** " (format "%s" value) "\n\n")))

(defun shopify-liquid-docs--insert-section (title body)
  "Insert a markdown section with TITLE and BODY text."
  (when (and body (not (string-empty-p body)))
    (insert "\n")
    (shopify-liquid-docs--insert-heading title 2)
    (insert "\n" body "\n")))

(defun shopify-liquid-docs--insert-code-block (code)
  "Insert CODE wrapped in a liquid markdown fenced code block."
  (when (and code (not (string-empty-p code)))
    (insert "```liquid\n" code "\n```\n")))

(defun shopify-liquid-docs--format-return-type (return-types)
  "Format RETURN-TYPES list into a readable string."
  (when return-types
    (mapconcat
     (lambda (rt)
       (let ((type (alist-get 'type rt))
             (name (shopify-liquid-docs--get rt 'name))
             (array-value (shopify-liquid-docs--get rt 'array_value)))
         (cond
          (array-value (format "`array<%s>`" array-value))
          (name (format "`%s` (%s)" type name))
          (t (format "`%s`" type)))))
     return-types " | ")))

(defun shopify-liquid-docs--format-parameters (params)
  "Format PARAMS list into readable markdown text."
  (when params
    (mapconcat
     (lambda (p)
       (let ((name (alist-get 'name p))
             (description (shopify-liquid-docs--get p 'description))
             (types (alist-get 'types p))
             (required (alist-get 'required p)))
         (format "- `%s`%s%s%s"
                 (or name "?")
                 (if types (format " (%s)" (mapconcat (lambda (ty) (format "`%s`" ty)) types ", ")) "")
                 (if required "" " *[optional]*")
                 (if description (format " — %s" description) ""))))
     params "\n")))

(defun shopify-liquid-docs--format-syntax-keywords (syntax-keywords)
  "Format SYNTAX-KEYWORDS list into readable markdown text."
  (when syntax-keywords
    (mapconcat
     (lambda (sk)
       (let ((keyword (shopify-liquid-docs--get sk 'keyword))
             (description (shopify-liquid-docs--get sk 'description)))
         (format "- `%s`%s"
                 (or keyword "?")
                 (if description (format " — %s" description) ""))))
     syntax-keywords "\n")))

(defun shopify-liquid-docs--format-examples (examples)
  "Format EXAMPLES list into readable markdown text."
  (when examples
    (let ((parts nil))
      (dolist (ex examples)
        (let ((name (shopify-liquid-docs--get ex 'name))
              (description (shopify-liquid-docs--get ex 'description))
              (syntax (shopify-liquid-docs--get ex 'syntax))
              (raw-liquid (shopify-liquid-docs--get ex 'raw_liquid)))
          (when (or name raw-liquid syntax)
            (push "" parts)
            (when name
              (push (format "### %s\n" name) parts))
            (when description
              (push (concat description "\n") parts))
            (when syntax
              (push (format "```liquid\n%s\n```\n" syntax) parts))
            (when raw-liquid
              (push (format "```liquid\n%s\n```\n" raw-liquid) parts)))))
      (string-join (nreverse parts) "\n"))))

(defun shopify-liquid-docs--format-properties (properties)
  "Format object PROPERTIES list into markdown."
  (when properties
    (mapconcat
     (lambda (prop)
       (let ((name (alist-get 'name prop))
             (summary (shopify-liquid-docs--get prop 'summary))
             (deprecated (alist-get 'deprecated prop))
             (return-type (alist-get 'return_type prop)))
         (format "- `%s`%s%s%s"
                 (or name "?")
                 (if return-type
                     (format " → %s" (shopify-liquid-docs--format-return-type return-type))
                   "")
                 (if (eq deprecated t) " **[DEPRECATED]**" "")
                 (if summary (format " — %s" summary) ""))))
     properties "\n")))

(defun shopify-liquid-docs--format-access (access)
  "Format ACCESS information for an object."
  (when access
    (let ((global (alist-get 'global access))
          (parents (alist-get 'parents access))
          (templates (alist-get 'template access))
          (parts nil))
      (when (eq global t)
        (push "Global" parts))
      (when parents
        (dolist (p parents)
          (let ((obj (alist-get 'object p))
                (prop (alist-get 'property p)))
            (push (format "`%s.%s`" obj prop) parts))))
      (when templates
        (dolist (tpl templates)
          (push (format "template: %s" tpl) parts)))
      (when parts
        (string-join (nreverse parts) ", ")))))

;;; --- Rendering Entries ---

(defun shopify-liquid-docs--render-filter (entry)
  "Render a filter ENTRY as markdown into the current buffer."
  (let ((name (alist-get 'name entry))
        (summary (shopify-liquid-docs--get entry 'summary))
        (description (shopify-liquid-docs--get entry 'description))
        (syntax (shopify-liquid-docs--get entry 'syntax))
        (category (shopify-liquid-docs--get entry 'category))
        (deprecated (alist-get 'deprecated entry))
        (deprecation-reason (shopify-liquid-docs--get entry 'deprecation_reason))
        (return-type (alist-get 'return_type entry))
        (parameters (alist-get 'parameters entry))
        (examples (alist-get 'examples entry)))
    (shopify-liquid-docs--insert-heading (format "Filter: %s" name) 1)
    (insert "\n")
    (when (eq deprecated t)
      (insert "**DEPRECATED**"
              (if deprecation-reason (format " — %s" (shopify-liquid-docs--decode-entities deprecation-reason)) "")
              "\n\n"))
    (when summary (insert summary "\n\n"))
    (shopify-liquid-docs--insert-field "Category" category)
    (when syntax
      (insert "**Syntax:**\n\n")
      (shopify-liquid-docs--insert-code-block syntax)
      (insert "\n"))
    (shopify-liquid-docs--insert-field "Returns" (shopify-liquid-docs--format-return-type return-type))
    (shopify-liquid-docs--insert-section "Description" description)
    (let ((param-text (shopify-liquid-docs--format-parameters parameters)))
      (shopify-liquid-docs--insert-section "Parameters" param-text))
    (let ((example-text (shopify-liquid-docs--format-examples examples)))
      (shopify-liquid-docs--insert-section "Examples" example-text))))

(defun shopify-liquid-docs--render-object (entry)
  "Render an object ENTRY as markdown into the current buffer."
  (let ((name (alist-get 'name entry))
        (summary (shopify-liquid-docs--get entry 'summary))
        (description (shopify-liquid-docs--get entry 'description))
        (deprecated (alist-get 'deprecated entry))
        (deprecation-reason (shopify-liquid-docs--get entry 'deprecation_reason))
        (access (alist-get 'access entry))
        (properties (alist-get 'properties entry))
        (return-type (alist-get 'return_type entry))
        (examples (alist-get 'examples entry)))
    (shopify-liquid-docs--insert-heading (format "Object: %s" name) 1)
    (insert "\n")
    (when (eq deprecated t)
      (insert "**DEPRECATED**"
              (if deprecation-reason (format " — %s" (shopify-liquid-docs--decode-entities deprecation-reason)) "")
              "\n\n"))
    (when summary (insert summary "\n\n"))
    (shopify-liquid-docs--insert-field "Access" (shopify-liquid-docs--format-access access))
    (shopify-liquid-docs--insert-field "Returns" (shopify-liquid-docs--format-return-type return-type))
    (shopify-liquid-docs--insert-section "Description" description)
    (let ((prop-text (shopify-liquid-docs--format-properties properties)))
      (shopify-liquid-docs--insert-section "Properties" prop-text))
    (let ((example-text (shopify-liquid-docs--format-examples examples)))
      (shopify-liquid-docs--insert-section "Examples" example-text))))

(defun shopify-liquid-docs--render-tag (entry)
  "Render a tag ENTRY as markdown into the current buffer."
  (let ((name (alist-get 'name entry))
        (summary (shopify-liquid-docs--get entry 'summary))
        (description (shopify-liquid-docs--get entry 'description))
        (syntax (shopify-liquid-docs--get entry 'syntax))
        (category (shopify-liquid-docs--get entry 'category))
        (deprecated (alist-get 'deprecated entry))
        (deprecation-reason (shopify-liquid-docs--get entry 'deprecation_reason))
        (parameters (alist-get 'parameters entry))
        (syntax-keywords (alist-get 'syntax_keywords entry))
        (examples (alist-get 'examples entry)))
    (shopify-liquid-docs--insert-heading (format "Tag: %s" name) 1)
    (insert "\n")
    (when (eq deprecated t)
      (insert "**DEPRECATED**"
              (if deprecation-reason (format " — %s" (shopify-liquid-docs--decode-entities deprecation-reason)) "")
              "\n\n"))
    (when summary (insert summary "\n\n"))
    (shopify-liquid-docs--insert-field "Category" category)
    (when syntax
      (insert "**Syntax:**\n\n")
      (shopify-liquid-docs--insert-code-block syntax)
      (insert "\n"))
    (shopify-liquid-docs--insert-section "Description" description)
    (let ((sk-text (shopify-liquid-docs--format-syntax-keywords syntax-keywords)))
      (shopify-liquid-docs--insert-section "Syntax Keywords" sk-text))
    (let ((param-text (shopify-liquid-docs--format-parameters parameters)))
      (shopify-liquid-docs--insert-section "Parameters" param-text))
    (let ((example-text (shopify-liquid-docs--format-examples examples)))
      (shopify-liquid-docs--insert-section "Examples" example-text))))

;;; --- Display ---

(defun shopify-liquid-docs--display (type entry)
  "Display documentation for ENTRY of TYPE in a dedicated buffer."
  (let ((buf (get-buffer-create "*Shopify Liquid Docs*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (pcase type
          ('filter (shopify-liquid-docs--render-filter entry))
          ('object (shopify-liquid-docs--render-object entry))
          ('tag (shopify-liquid-docs--render-tag entry)))
        (goto-char (point-min)))
      (shopify-liquid-docs-view-mode))
    (pop-to-buffer buf)))

;;; --- View Mode ---

(defvar shopify-liquid-docs-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "f" #'shopify-liquid-docs-filters)
    (define-key map "o" #'shopify-liquid-docs-objects)
    (define-key map "t" #'shopify-liquid-docs-tags)
    (define-key map "s" #'shopify-liquid-docs-search)
    map)
  "Keymap for `shopify-liquid-docs-view-mode'.")

(define-derived-mode shopify-liquid-docs-view-mode markdown-view-mode "Liquid-Docs"
  "Major mode for viewing Shopify Liquid documentation.
Inherits from `markdown-view-mode' for rendering.

\\{shopify-liquid-docs-view-mode-map}")

;;; --- Completion & Search ---

(defun shopify-liquid-docs--candidates (type entries)
  "Build completion candidates from ENTRIES with TYPE prefix.
Returns an alist of (display-string . (type . entry))."
  (mapcar
   (lambda (entry)
     (let* ((name (alist-get 'name entry))
            (summary (or (shopify-liquid-docs--get entry 'summary) ""))
            (deprecated (if (eq (alist-get 'deprecated entry) t) " [DEPRECATED]" ""))
            (display (format "%-30s %s%s" name summary deprecated)))
       (cons display (cons type entry))))
   entries))

;;;###autoload
(defun shopify-liquid-docs-filters ()
  "Browse Shopify Liquid filters with completion."
  (interactive)
  (shopify-liquid-docs--ensure-loaded)
  (let* ((candidates (shopify-liquid-docs--candidates 'filter shopify-liquid-docs--filters))
         (choice (completing-read "Filter: " candidates nil t))
         (selected (cdr (assoc choice candidates))))
    (shopify-liquid-docs--display (car selected) (cdr selected))))

;;;###autoload
(defun shopify-liquid-docs-objects ()
  "Browse Shopify Liquid objects with completion."
  (interactive)
  (shopify-liquid-docs--ensure-loaded)
  (let* ((candidates (shopify-liquid-docs--candidates 'object shopify-liquid-docs--objects))
         (choice (completing-read "Object: " candidates nil t))
         (selected (cdr (assoc choice candidates))))
    (shopify-liquid-docs--display (car selected) (cdr selected))))

;;;###autoload
(defun shopify-liquid-docs-tags ()
  "Browse Shopify Liquid tags with completion."
  (interactive)
  (shopify-liquid-docs--ensure-loaded)
  (let* ((candidates (shopify-liquid-docs--candidates 'tag shopify-liquid-docs--tags))
         (choice (completing-read "Tag: " candidates nil t))
         (selected (cdr (assoc choice candidates))))
    (shopify-liquid-docs--display (car selected) (cdr selected))))

;;;###autoload
(defun shopify-liquid-docs-search ()
  "Search across all Shopify Liquid filters, objects, and tags."
  (interactive)
  (shopify-liquid-docs--ensure-loaded)
  (let* ((filter-candidates
          (mapcar (lambda (c)
                    (cons (format "[filter] %s" (car c)) (cdr c)))
                  (shopify-liquid-docs--candidates 'filter shopify-liquid-docs--filters)))
         (object-candidates
          (mapcar (lambda (c)
                    (cons (format "[object] %s" (car c)) (cdr c)))
                  (shopify-liquid-docs--candidates 'object shopify-liquid-docs--objects)))
         (tag-candidates
          (mapcar (lambda (c)
                    (cons (format "[tag]    %s" (car c)) (cdr c)))
                  (shopify-liquid-docs--candidates 'tag shopify-liquid-docs--tags)))
         (all (append filter-candidates object-candidates tag-candidates))
         (choice (completing-read "Liquid docs: " all nil t))
         (selected (cdr (assoc choice all))))
    (shopify-liquid-docs--display (car selected) (cdr selected))))

;;;###autoload
(defun shopify-liquid-docs-lookup ()
  "Look up the symbol at point in Shopify Liquid docs."
  (interactive)
  (shopify-liquid-docs--ensure-loaded)
  (let* ((sym (or (thing-at-point 'symbol t) ""))
         (all-entries
          (append
           (mapcar (lambda (e) (cons 'filter e)) shopify-liquid-docs--filters)
           (mapcar (lambda (e) (cons 'object e)) shopify-liquid-docs--objects)
           (mapcar (lambda (e) (cons 'tag e)) shopify-liquid-docs--tags)))
         (match (seq-find (lambda (pair)
                            (string-equal-ignore-case sym (alist-get 'name (cdr pair))))
                          all-entries)))
    (if match
        (shopify-liquid-docs--display (car match) (cdr match))
      (let ((input (completing-read (format "No match for '%s'. Search: " sym)
                                    (mapcar (lambda (pair)
                                              (alist-get 'name (cdr pair)))
                                            all-entries)
                                    nil t)))
        (when-let* ((found (seq-find (lambda (pair)
                                       (string-equal-ignore-case input (alist-get 'name (cdr pair))))
                                     all-entries)))
          (shopify-liquid-docs--display (car found) (cdr found)))))))

;;;###autoload
(defun shopify-liquid-docs-refresh ()
  "Re-download and reload all documentation data."
  (interactive)
  (shopify-liquid-docs-download))

(provide 'shopify-liquid-docs)
;;; shopify-liquid-docs.el ends here
