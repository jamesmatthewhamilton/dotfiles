;; Author: James Matthew Hamilton
;;
;; Tip: Refresh init.el with 'M-x eval-buffer' for testing changes.
;;
;; --- Table of Contents ---
;;  I.   Library Setup
;;  II.  Variables
;;  III. Emacs Base
;;  IV.  Keybindings
;;  V.   Language Specific
;;  VI.  Library Specific
;;  VII. Project Specific


;; ------------------------ I. Library Setup ------------------------

;; open in os's full-screen mode
(add-to-list 'default-frame-alist '(fullscreen . fullboth))

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
      '(use-package           ;; package config macro
	string-inflection     ;; case conversion utils
	doom-themes           ;; color theme most maintained
        lsp-mode              ;; language server protocol
        yasnippet             ;; optional lsp-mode
        company               ;; optional lsp-mode
        org                   ;; org-mode
        magit                 ;; git porcelain
        ;; ...
        ))

;; ensures missing packages are installed
(unless (cl-every #'package-installed-p my-required-packages)
  (package-refresh-contents)
  (dolist (package my-required-packages)
    (unless (package-installed-p package)
      (package-install package))))


;; ------------------------ II. Variables  ------------------------

(defvar my-max-col 85 "Max column width.")


;; ------------------------ III. Emacs Base  ------------------------

;; global theme
;; (load-theme 'doom-ayu-dark t)  ;; 7 without comments, 9 with comments
(load-theme 'doom-fairy-floss t)  ;; 9.5 without background, 7 with background
;; (load-theme 'doom-laserwave t)  ;; 8 without background, 6 with background
;; (load-theme 'doom-moonlight t)  ;; 7
;; (load-theme 'doom-outrun-electric t)  ;; 8
;; (load-theme 'doom-molokai t)  ;; 8.5

;; [WARNING] comment this before testing new themes
;; overwrites theme colors with custom colors
(custom-set-faces
 '(default ((t (:background "#0B0E14"))))
 '(font-lock-comment-face ((t (:foreground "#9E7A8A")))))

;; always end a file with a newline
(setq require-final-newline t)

;; don't let `next-line' add new lines in buffer
(setq next-line-add-newlines nil)

;; forces \n while typing comments after length N
(setq-default fill-column my-max-col)

;; when pressing \n the default-fill-column will kick-in
(setq comment-auto-fill-only-comments t)
(add-hook 'prog-mode-hook 'auto-fill-mode)

;; delete trailing white-s-modpace before save
(add-hook 'before-save-hook 'delete-trailing-whitespace)

;; use spaces instead of tabs
(setq-default indent-tabs-mode nil)

;; load last buffers that were open
(desktop-save-mode 1)

;; begging for no top bar
(menu-bar-mode -1)
(tool-bar-mode -1)

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

;; show line and column num as L{$N} C{$N}
(setq mode-line-position '(" L%l C%c"))

;; max column width before red angry highlight
(setq whitespace-line-column my-max-col)

;; confirm on kill, because we fat-finger C-x C-c so often
;;(add-hook 'kill-emacs-query-functions
;;          (lambda () (y-or-n-p "Do you really want to exit Emacs? "))
;;          'append)

;; set font size
(set-face-attribute 'default nil :height 120)

;; backups and auto-saves: keep them out of source directories
(let ((backup-dir (expand-file-name "backups/" user-emacs-directory))
      (auto-save-dir (expand-file-name "auto-saves/" user-emacs-directory)))
  (make-directory backup-dir t)
  (make-directory auto-save-dir t)
  (set-file-modes backup-dir #o700)
  (set-file-modes auto-save-dir #o700)
  (setq backup-directory-alist `(("." . ,backup-dir)))
  (setq auto-save-file-name-transforms `((".*" ,auto-save-dir t))))

(setq backup-by-copying t
      backup-by-copying-when-mismatch t
      version-control t
      kept-new-versions 6
      kept-old-versions 2
      delete-old-versions t)

;; set font size to fill N columns perfectly
(defun my/fit-font-for-splits (splits &optional target-cols)
  "Set default face height so SPLITS side-by-side windows fit TARGET-COLS chars each."
  (let* ((target-cols (or target-cols 85))
         (frame-px (frame-pixel-width))
         (overhead (* splits 30))
         (px-per-col (/ (float (- frame-px overhead)) (* splits target-cols)))
         (height (round (* (/ px-per-col 0.6) 10))))
    (set-face-attribute 'default nil :height height)
    (message "splits=%d height=%d" splits height)))

(defun my/fit-font-2-split ()
  "Fit font for 2-window horizontal split at 85 cols each."
  (interactive)
  (my/fit-font-for-splits 2))

(defun my/fit-font-3-split ()
  "Fit font for 3-window horizontal split at 85 cols each."
  (interactive)
  (my/fit-font-for-splits 3))

(defun my/fit-font-4-split ()
  "Fit font for 4-window horizontal split at 85 cols each."
  (interactive)
  (my/fit-font-for-splits 4))

;; set font size by default to fill 2 screens
(add-hook 'window-setup-hook #'my/fit-font-2-split)

;; ------------------------ IV. Peronsal Keybindings ------------------------
;; tip: S-C = control-shift

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


;; ------------------------ V. Langauge Specific ------------------------

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
(add-hook 'c++-mode-hook (lambda ()
  (setq tab-width 4)
  (setq indent-tabs-mode nil)
  (setq c-basic-offset 4)
  (setq c-auto-newline nil)
  (whitespace-mode)))
(add-hook 'c-mode-hook (lambda ()
  (setq tab-width 4)
  (setq indent-tabs-mode nil)
  (setq c-basic-offset 4)
  (whitespace-mode)))

;; Test for treating XML like HTML
(setq auto-mode-alist (cons '("\\.xml\\'" . html-mode) auto-mode-alist))

;; XML-mode hack.. (?)
(put 'xml-mode 'font-lock-defaults '(html-font-lock-keywords nil t))


;; ------------------------ VI. Libraries Specific ------------------------

;; lsp
;; (add-hook 'c-mode-hook #'lsp)
;; (add-hook 'c++-mode-hook #'lsp)

;; solves the flymake-cc/lsp-mode conflic
(with-eval-after-load 'flymake-cc
  (defun flymake-cc (_report-fn &rest _args) nil))

;; org-mode
(require 'org)
(define-key global-map "\C-cl" 'org-store-link)
(define-key global-map "\C-ca" 'org-agenda)
(setq org-log-done t)

;; ------------------------ VII. Remote Connections ------------------------


;; ------------------------ VIII. Project Specific ------------------------
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(company yasnippet use-package string-inflection solarized-theme magit lsp-mode doom-themes)))
