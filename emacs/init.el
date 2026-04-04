;; Author: James Matthew Hamilton
;;
;; Tip: Refresh init.el with 'M-x eval-buffer' for testing changes.
;;
;; Table of Contents:
;;  I.   Library Setup
;;  II.  Emacs Base
;;  III. Keybindings
;;  IV.  Language Specific
;;  V.   Library Specific

;; ------------------------ Library Setup ------------------------

;; repos
(require 'package)
(setq package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("melpa" . "https://melpa.org/packages/")
                         ;; ...
                         ))
(package-initialize)

;; required packages
;; hint: see "list-packages" for more info.
(setq my-required-packages
      '(use-package
	string-inflection
        solarized-theme
        lsp-mode
        org
        ;; ...

        ))

;; ensures missing packages are installed
(dolist (package my-required-packages)
  (unless (package-installed-p package)
    (unless (assoc package package-archive-contents)
      (package-refresh-contents))
    (package-install package)))

;; ------------------------ Emacs Base  ------------------------

;; global theme
(load-theme 'solarized-wombat-dark t)

;; always end a file with a newline
(setq require-final-newline t)

;; don't let `next-line' add new lines in buffer
(setq next-line-add-newlines nil)

;; set default-fill-column length
(setq default-fill-column 100)

;; when pressing \n the default-fill-column will kick-in
(setq comment-auto-fill-only-comments t)
(add-hook 'prog-mode-hook 'auto-fill-mode)

;; delete trailing white-s-modpace before save
(add-hook 'before-save-hook 'delete-trailing-whitespace)

;; use spaces instead of tabs
(setq-default indent-tabs-mode nil)

;; load last buffers that were open
(desktop-save-mode 1)

;; reload last buffers including ssh sessions
;; note: if starting emacs with ssh buffers and forgot vpn,
;;       close emacs, connect to vpn, start emacs again and
;;       ssh buffers will still be there
(setq tramp-default-method "ssh")
(setq desktop-buffers-not-to-save "^$")
(setq desktop-files-not-to-save "^$")

;; display line numbers in all buffers
;; (global-display-line-numbers-mode)

;; turn off all sorts of progressive mouse wheel scrolling
(setq mouse-wheel-progressive-speed nil)
(setq mouse-wheel-follow-mouse 't)
(setq scroll-step 1)

;; turn off that DANG keyboard bell
(setq visible-bell 'top-bottom)

;; stop emacs from printing its banner every time it is invoked
(setq inhibit-startup-message t)

;; confirm on kill, because we fat-finger C-x C-c so often
;;(add-hook 'kill-emacs-query-functions
;;          (lambda () (y-or-n-p "Do you really want to exit Emacs? "))
;;          'append)

;; set font size
(set-face-attribute 'default nil :height 100)
(add-hook 'find-file-hook (lambda () (set-face-attribute 'default nil :height 100)))

;; Backup and auto-save files
(make-directory "~/.emacs.d/backups" t)
(set-file-modes "~/.emacs.d/backups" #o700)
(setq backup-directory-alist '(("." . "~/.emacs.d/backups")))
(setq backup-by-copying t)
;; Force backup files to be owner-only (TRAMP copies remote permissions otherwise)
(setq backup-by-copying-when-mismatch t)
(defun force-backup-permissions ()
  "Set backup file permissions to 600 after creation."
  (when (and buffer-file-name backup-directory-alist)
    (let ((backup (car (find-backup-file-name buffer-file-name))))
      (when (and backup (file-exists-p backup))
        (set-file-modes backup #o600)))))
(add-hook 'after-save-hook #'force-backup-permissions)
(defcustom auto-save-dir-base "~/.emacs.d/backups"
  "File name base for auto-save-dir.
The real auto save directory name is created by appending the UID of the user.
/Restart of emacs required after changes."
  :group 'files
  :type 'directory)
(defun auto-save-ensure-dir ()
  "Ensure that the directory of `buffer-auto-save-file-name' exists.
Can be used in `auto-save-hook'."
  (cl-loop for buf in (buffer-list) do
       (with-current-buffer buf
         (when (and (buffer-file-name) ;; Is this buffer associated with a file?
            (stringp buffer-auto-save-file-name)) ;; Does it have an auto-save-file?
           (let ((dir (file-name-directory buffer-auto-save-file-name)))
         (unless (file-directory-p dir)
           (make-directory dir t)
           ))))))
(add-hook 'auto-save-hook #'auto-save-ensure-dir)
(defun auto-save-dir ()
  "Return the users auto save directory."
  (concat auto-save-dir-base (number-to-string (user-uid))))
(unless (file-directory-p (auto-save-dir))
  (make-directory (auto-save-dir)))
(add-to-list 'auto-save-file-name-transforms (list "\\`.*\\'" (concat (auto-save-dir) "\\&") nil) t)


;; ------------------------ Peronsal Keybindings ------------------------
;; Tip: S-C = Control-Shift

(global-set-key (kbd "M-C-<down>") 'scroll-up-line)
(global-set-key (kbd "M-C-<up>") 'scroll-down-line)
(global-set-key (kbd "S-C-<left>") 'shrink-window-horizontally)
(global-set-key (kbd "S-C-<right>") 'enlarge-window-horizontally)
(global-set-key (kbd "S-C-<down>") 'shrink-window)
(global-set-key (kbd "S-C-<up>") 'enlarge-window)
(global-set-key (kbd "M-g") 'goto-line)
(global-set-key (kbd "C-<tab>") 'other-window)
(global-set-key (kbd "M-s") 'whitespace-mode)
(global-set-key (kbd "M-l") 'global-display-line-numbers-mode)

;; ------------------------ Langauge Specific ------------------------

; set up thise comment column
(setq comment-column 40)
;;; Tell emacs which package to use depending on suffix
(setq auto-mode-alist (append '(("\\.cc$" . c++-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.hxx$" . c++-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.cxx$" . c++-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.hpp$" . c++-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.cpp$" . c++-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.h$" . c-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.h$" . c-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.c$" . c-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.C$" . c-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.l$" . c-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.y$" . c-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.cu$" . c-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("Makefile" . makefile-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("makefile" . makefile-mode)) auto-mode-alist))
(setq auto-mode-alist (append '(("\\.pl$" . perl-mode)) auto-mode-alist))
(setq auto-mode-alist (cons '("\\.xml$" . nxml-mode) auto-mode-alist))
(setq auto-mode-alist (cons '("\\.xsl$" . nxml-mode) auto-mode-alist))

;; No auto-newline in c / c++ after {,} and stuff
(setq c-auto-newline 'nil)
(setq c-default-style "linux")
(add-hook 'c++-mode-hook '(lambda ()
  (setq tab-width 4)
  (setq indent-tabs-mode nil)
  (setq c-basic-offset 4)
  (setq c-auto-newline nil)
  (whitespace-mode)))
(add-hook 'c-mode-hook '(lambda ()
  (setq tab-width 4)
  (setq indent-tabs-mode nil)
  (setq c-basic-offset 4)
  (whitespace-mode)))

;; Test for treating XML like HTML
(setq auto-mode-alist (cons '("\\.xml\\'" . html-mode) auto-mode-alist))

;; XML-mode hack.. (?)
(put 'xml-mode 'font-lock-defaults '(html-font-lock-keywords nil t))

;; ------------------------ Libraries Specific ------------------------
;; Org-Mode
(require 'org)
(define-key global-map "\C-cl" 'org-store-link)
(define-key global-map "\C-ca" 'org-agenda)
(setq org-log-done t)
(custom-set-variables
 '(package-selected-packages '(lsp-mode solarized-theme string-inflection use-package)))
