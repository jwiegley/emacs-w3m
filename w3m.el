;;; -*- mode: Emacs-Lisp; coding: euc-japan -*-

;; Copyright (C) 2000,2001 TSUCHIYA Masatoshi <tsuchiya@pine.kuee.kyoto-u.ac.jp>

;; Authors: TSUCHIYA Masatoshi <tsuchiya@pine.kuee.kyoto-u.ac.jp>,
;;          Shun-ichi GOTO     <gotoh@taiyo.co.jp>,
;;          Satoru Takabayashi <satoru-t@is.aist-nara.ac.jp>,
;;          Hideyuki SHIRAI    <shirai@meadowy.org>,
;;          Keisuke Nishida    <kxn30@po.cwru.edu>,
;;          Yuuichi Teranishi  <teranisi@gohome.org>
;; Keywords: w3m, WWW, hypermedia

;; w3m.el is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.

;; w3m.el is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with w3m.el; if not, write to the Free Software Foundation,
;; Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


;;; Commentary:

;; w3m.el is the interface program of w3m on Emacs.  For more detail
;; about w3m, see:
;;
;;    http://ei5nazha.yz.yamagata-u.ac.jp/~aito/w3m/


;;; How to install:

;; Please put this file to appropriate directory, and if you want
;; byte-compile it.  And add following lisp expressions to your
;; ~/.emacs.
;;
;;     (autoload 'w3m "w3m" "Interface for w3m on Emacs." t)


;;; Code:

(eval-and-compile
  (or (and (boundp 'emacs-major-version)
	   (>= emacs-major-version 20))
      (progn
	(require 'poe)
	(require 'pcustom))))

(if (featurep 'xemacs)
    (require 'poem))

(require 'thingatpt)

;; this package using a few CL macros
(eval-when-compile (require 'cl))

(put 'w3m-static-if 'lisp-indent-function 2)
(defmacro w3m-static-if (cond then &rest else)
  (if (eval cond) then (` (progn  (,@ else)))))

(w3m-static-if (not (fboundp 'find-coding-system))
    (w3m-static-if (fboundp 'coding-system-p)
	(defsubst find-coding-system (obj)
	  "Return OBJ if it is a coding-system."
	  (if (coding-system-p obj) obj))
      (require 'pces)))

(defconst emacs-w3m-version
  (eval-when-compile
    (let ((rev "$Revision: 1.86 $"))
      (and (string-match "\\.\\([0-9]+\\) \$$" rev)
	   (format "0.2.%d"
		   (- (string-to-number (match-string 1 rev)) 28)))))
  "Version number of this package.")

(defgroup w3m nil
  "w3m - the web browser of choice."
  :group 'hypermedia)

(defgroup w3m-face nil
  "Faces for w3m."
  :group 'w3m
  :prefix "w3m-")

(defcustom w3m-command "w3m"
  "*Name of the executable file of w3m."
  :group 'w3m
  :type 'string)

(defcustom w3m-fill-column -1
  "*Fill column of w3m.
Value is integer.
Positive value is for fixed column rendering.
Zero or negative value is for fitting w3m output with current frame
width using expression (+ (frame-width) VALUE)."
  :group 'w3m
  :type 'integer)

(defcustom w3m-mailto-url-function nil
  "*Mailto handling Function."
  :group 'w3m
  :type 'function)

(defcustom w3m-coding-system
  (w3m-static-if (boundp 'MULE) '*euc-japan* 'euc-japan)
  "*Coding system for w3m."
  :group 'w3m
  :type 'symbol)

(defcustom w3m-input-coding-system
  (w3m-static-if (boundp 'MULE) '*iso-2022-jp* 'iso-2022-jp)
  "*Coding system for w3m."
  :group 'w3m
  :type 'symbol)

(defcustom w3m-output-coding-system
  (w3m-static-if (boundp 'MULE) '*euc-japan* 'euc-japan)
  "*Coding system for w3m."
  :group 'w3m
  :type 'symbol)

(defcustom w3m-default-url-coding-system
  (w3m-static-if (boundp 'MULE) '*euc-japan* 'euc-japan)
  "*Coding system to encode search query string.
This value is default and used only when spec defined by
`w3m-search-engine-alist' does not have encoding information."
  :group 'w3m
;  :type 'string)
  :type '(restricted-sexp :match-alternatives (coding-system-p)))

(defcustom w3m-use-cygdrive t
  "*If non-nil, use /cygdrive/ rule when expand-file-name."
  :group 'w3m
  :type 'boolean)

(defcustom w3m-profile-directory "~/.w3m"
  "*Directory of w3m profiles."
  :group 'w3m
  :type 'directory)

(defcustom w3m-default-save-directory "~/.w3m"
  "*Default directory for save file."
  :group 'w3m
  :type 'directory)

(defcustom w3m-delete-duplicated-empty-lines t
  "*Compactize page by deleting duplicated empty lines."
  :group 'w3m
  :type 'boolean)

(defcustom w3m-display-inline-image nil
  "*Display inline images."
  :group 'w3m
  :type 'boolean)

(defun w3m-url-to-file-name (url)
  (if (string-match "^file:" url)
      (setq url (substring url (match-end 0))))
  (if (string-match "^\\(//\\|/cygdrive/\\)\\(.\\)/\\(.*\\)" url)
      (setq url (concat (match-string 2 url) ":/" (match-string 3 url))))
  url)

(defun w3m-expand-file-name-as-url (file &optional directory)
  ;; if filename is cygwin format,
  ;; then remove cygdrive prefix before expand-file-name
  (if directory
      (setq file (w3m-url-to-file-name file)))
  ;; expand to file scheme url considering Win32 environment
  (setq file (expand-file-name file directory))
  (if (string-match "^\\(.\\):\\(.*\\)" file)
      (if w3m-use-cygdrive
	  (concat "/cygdrive/" (match-string 1 file) (match-string 2 file))
	(concat "file://" (match-string 1 file) (match-string 2 file)))
    file))

(defcustom w3m-bookmark-file
  (expand-file-name "bookmark.html" w3m-profile-directory)
  "*Bookmark file of w3m."
  :group 'w3m
  :type 'file)

(defcustom w3m-bookmark-file-coding-system
  (w3m-static-if (boundp 'MULE) '*euc-japan* 'euc-japan)
  "*Coding system for bookmark file."
  :group 'w3m
  :type 'symbol)

(defcustom w3m-home-page
  (or (getenv "HTTP_HOME")
      (getenv "WWW_HOME")
      (if (file-readable-p w3m-bookmark-file)
	  (w3m-expand-file-name-as-url w3m-bookmark-file)
	"http://namazu.org/~tsuchiya/emacs-w3m/"))
  "*Home page of w3m.el."
  :group 'w3m
  :type 'string)

(defcustom w3m-arrived-file
  (expand-file-name ".arrived" w3m-profile-directory)
  "*File which has list of arrived URLs."
  :group 'w3m
  :type 'file)

(defcustom w3m-arrived-file-coding-system
  (w3m-static-if (boundp 'MULE) '*euc-japan 'euc-japan)
  "*Coding system for arrived file."
  :group 'w3m
  :type 'symbol)

(defcustom w3m-keep-arrived-urls 500
  "*Arrived keep count of w3m."
  :group 'w3m
  :type 'integer)

(defcustom w3m-keep-cache-size 300
  "*Cache size of w3m."
  :group 'w3m
  :type 'integer)

(defface w3m-anchor-face
  '((((class color) (background light)) (:foreground "blue" :underline t))
    (((class color) (background dark)) (:foreground "cyan" :underline t))
    (t (:underline t)))
  "*Face to fontify anchors."
  :group 'w3m-face)

(defface w3m-arrived-anchor-face
  '((((class color) (background light)) (:foreground "navy" :underline t))
    (((class color) (background dark)) (:foreground "LightSkyBlue" :underline t))
    (t (:underline t)))
  "*Face to fontify anchors, if arrived."
  :group 'w3m-face)

(defface w3m-image-face
  '((((class color) (background light)) (:foreground "ForestGreen"))
    (((class color) (background dark)) (:foreground "PaleGreen"))
    (t (:underline t)))
  "*Face to fontify image alternate strings."
  :group 'w3m-face)

(defface w3m-form-face
  '((((class color) (background light)) (:foreground "cyan" :underline t))
    (((class color) (background dark)) (:foreground "red" :underline t))
    (t (:underline t)))
  "*Face to fontify forms."
  :group 'w3m-face)

(defcustom w3m-hook nil
  "*Hook run before w3m called."
  :group 'w3m
  :type 'hook)

(defcustom w3m-mode-hook nil
  "*Hook run before w3m-mode called."
  :group 'w3m
  :type 'hook)

(defcustom w3m-fontify-before-hook nil
  "*Hook run before w3m-fontify called."
  :group 'w3m
  :type 'hook)

(defcustom w3m-fontify-after-hook nil
  "*Hook run after w3m-fontify called."
  :group 'w3m
  :type 'hook)

(defcustom w3m-async-exec nil
  "*If non-nil, w3m is executed an asynchronously process."
  :group 'w3m
  :type 'boolean)

(defcustom w3m-process-connection-type t
  "*Process connection type for w3m execution."
  :group 'w3m
  :type 'boolean)

(defcustom w3m-executable-type
  (if (memq window-system '(w32 win32))
      'cygwin ; xxx, cygwin on win32 by default
    'native)
  "*Executable binary type of w3m program.
Value is 'native or 'cygwin.
This value is maily used for win32 environment.
In other environment, use 'native."
  :group 'w3m
  :type '(choice (const cygwin) (const native)))

;; FIXME: 本当は mailcap を適切に読み込んで設定する必要がある
(defcustom w3m-content-type-alist
  '(("text/plain" "\\.\\(txt\\|tex\\|el\\)" nil)
    ("text/html" "\\.s?html?$" ("netscape" url))
    ("image/jpeg" "\\.jpe?g$" ("xv" file))
    ("image/png" "\\.png$" ("xv" file))
    ("image/gif" "\\gif$" ("xv" file))
    ("image/tiff" "\\tif?f$" ("xv" file))
    ("image/x-xwd" "\\.xwd$" ("xv" file))
    ("image/x-xbm" "\\.xbm$" ("xv" file))
    ("image/x-xpm" "\\.xpm$" ("xv" file))
    ("image/x-bmp" "\\.bmp$" ("xv" file))
    ("video/mpeg" "\\.mpe?g$" ("mpeg_play" file))
    ("video/quicktime" "\\.mov$" ("mpeg_play" file))
    ("application/postscript" "\\.\\(ps\\|eps\\)$" ("gv" file))
    ("application/pdf" "\\.pdf$" ("acroread" file)))
  "Alist of file suffixes vs. content type."
  :group 'w3m
  :type '(repeat
	  (list
	   (string :tag "Type")
	   (string :tag "Regexp")
	   (choice
	    (const :tag "None" nil)
	    (cons :tag "Externai viewer"
		  (string :tag "Command")
		  (repeat :tag "Arguments"
			  (restricted-sexp :match-alternatives
					   (stringp 'file 'url))))
	    (function :tag "Function")))))

(defcustom w3m-charset-coding-system-alist
  (let ((rest
	 '((us-ascii      . raw-text)
	   (gb2312	  . cn-gb-2312)
	   (cn-gb	  . cn-gb-2312)
	   (iso-2022-jp-2 . iso-2022-7bit-ss2)
	   (iso-2022-jp-3 . iso-2022-7bit-ss2)
	   (tis-620	  . tis620)
	   (windows-874	  . tis-620)
	   (cp874	  . tis-620)
	   (x-ctext       . ctext)
	   (unknown       . undecided)
	   (x-unknown     . undecided)
	   (euc-jp        . euc-japan)
	   (shift-jis     . shift_jis)
	   (shift_jis     . shift_jis)
	   (sjis          . shift_jis)
	   (x-euc-jp      . euc-japan)
	   (x-shift-jis   . shift_jis)
	   (x-shift_jis   . shift_jis)
	   (x-sjis        . shift_jis)))
	dest)
    (while rest
      (or (find-coding-system (car (car rest)))
	  (setq dest (cons (car rest) dest)))
      (setq rest (cdr rest)))
    dest)
  "Alist MIME CHARSET vs CODING-SYSTEM.
MIME CHARSET and CODING-SYSTEM must be symbol."
  :group 'w3m
  :type '(repeat (cons symbol coding-system)))

(defcustom w3m-search-engine-alist
  '(("yahoo" "http://search.yahoo.com/bin/search?p=%s" nil)
    ("yahoo-ja" "http://search.yahoo.co.jp/bin/search?p=%s" euc-japan)
    ("google" "http://www.google.com/search?q=%s" nil)
    ("google-ja" "http://www.google.com/search?q=%s&hl=ja&lr=" shift_jis)
    ("goo-ja" "http://www.goo.ne.jp/default.asp?MT=%s" euc-japan)
    ("rpmfind" "http://rpmfind.net/linux/rpm2html/search.php?query=%s"))
  "*An alist of search engines.
Each elemnt looks like (ENGINE ACTION CODING)
ENGINE is a string, the name of the search engine.
ACTION is a string, the URL that performs a search.
ACTION must contain a \"%s\", which is substituted by a query string.
CODING is optional value which is coding system for query string.
If omitted, `w3m-default-url-coding-system' is used.
"
  :group 'w3m
  :type '(repeat
	  (list
	   (string :tag "Engine")
	   (string :tag "Action")
	   (restricted-sexp :match-alternatives (coding-system-p nil)
			    :tag "Coding"))))

(defcustom w3m-default-search-engine "yahoo"
  "*Default search engine name.
See also `w3m-search-engine-alist'."
  :group 'w3m
  :type 'string)

(defcustom w3m-horizontal-scroll-columns 10
  "*Column size to scroll horizontaly."
  :group 'w3m
  :type 'integer)

(defcustom w3m-use-form nil
  "*Non-nil activates form extension. (EXPERIMENTAL)"
  :group 'w3m
  :type 'boolean)

(defconst w3m-weather-url-alist
  (eval-when-compile
    (let ((format "http://channel.goo.ne.jp/weather/area/%s.html")
	  (alist
	   '(("北海道・宗谷地方" . "011")
	     ("北海道・網走地方" . "021")
	     ("北海道・北見地方" . "022")
	     ("北海道・紋別地方" . "023")
	     ("北海道・上川地方" . "031")
	     ("北海道・留萌地方" . "032")
	     ("北海道・釧路地方" . "041")
	     ("北海道・根室地方" . "042")
	     ("北海道・十勝地方" . "043")
	     ("北海道・胆振地方" . "051")
	     ("北海道・日高地方" . "052")
	     ("北海道・石狩地方" . "061")
	     ("北海道・空知地方" . "062")
	     ("北海道・後志地方" . "063")
	     ("北海道・渡島地方" . "071")
	     ("北海道・檜山地方" . "072")
	     ("青森県・津軽地方" . "081")
	     ("青森県・下北地方" . "082")
	     ("青森県・三八上北地方" . "083")
	     ("秋田県・沿岸部" . "091")
	     ("秋田県・内陸部" . "092")
	     ("岩手県・内陸部" . "101")
	     ("岩手県・沿岸北部" . "102")
	     ("岩手県・沿岸南部" . "103")
	     ("山形県・村山地方" . "111")
	     ("山形県・置賜地方" . "112")
	     ("山形県・庄内地方" . "113")
	     ("山形県・最上地方" . "114")
	     ("宮城県・平野部" . "121")
	     ("宮城県・山沿い" . "122")
	     ("福島県・中通り" . "131")
	     ("福島県・浜通り" . "132")
	     ("福島県・会津地方" . "133")
	     ("新潟県・下越地方" . "141")
	     ("新潟県・中越地方" . "142")
	     ("新潟県・上越地方" . "143")
	     ("新潟県・佐渡島" . "144")
	     ("富山県・東部" . "151")
	     ("富山県・西部" . "152")
	     ("石川県・加賀地方" . "161")
	     ("石川県・能登地方" . "162")
	     ("福井県・嶺北" . "171")
	     ("福井県・嶺南" . "172")
	     ("栃木県・南部" . "181")
	     ("栃木県・北部" . "182")
	     ("群馬県・南部" . "191")
	     ("群馬県・北部" . "192")
	     ("埼玉県・南部" . "201")
	     ("埼玉県・北部" . "202")
	     ("埼玉県・秩父地方" . "203")
	     ("茨城県・北部" . "211")
	     ("茨城県・南部" . "212")
	     ("千葉県・北西部" . "221")
	     ("千葉県・北東部" . "222")
	     ("千葉県・南部" . "223")
	     ("東京都" . "231")
	     ("東京都・伊豆諸島北部" . "232")
	     ("東京都・伊豆諸島南部" . "233")
	     ("東京都・小笠原" . "234")
	     ("神奈川県・東部" . "261")
	     ("神奈川県・西部" . "262")
	     ("長野県・北部" . "271")
	     ("長野県・中部" . "272")
	     ("長野県・南部" . "273")
	     ("山梨県・中西部" . "281")
	     ("山梨県・東部富士五湖" . "282")
	     ("静岡県・中部" . "291")
	     ("静岡県・西部" . "292")
	     ("静岡県・東部" . "293")
	     ("静岡県・伊豆地方" . "294")
	     ("岐阜県・美濃地方" . "301")
	     ("岐阜県・飛騨地方" . "302")
	     ("三重県・北中部" . "311")
	     ("三重県・南部" . "312")
	     ("愛知県・西部" . "321")
	     ("愛知県・東部" . "322")
	     ("京都府・南部" . "331")
	     ("京都府・北部" . "332")
	     ("兵庫県・南部" . "341")
	     ("兵庫県・北部" . "342")
	     ("奈良県・北部" . "351")
	     ("奈良県・南部" . "352")
	     ("滋賀県・南部" . "361")
	     ("滋賀県・北部" . "362")
	     ("和歌山県・北部" . "371")
	     ("和歌山県・南部" . "372")
	     ("大阪府" . "381")
	     ("鳥取県・東部" . "391")
	     ("鳥取県・西部" . "392")
	     ("島根県・東部" . "401")
	     ("島根県・西部" . "402")
	     ("島根県・隠岐諸島" . "403")
	     ("岡山県・南部" . "411")
	     ("岡山県・北部" . "412")
	     ("広島県・南部" . "421")
	     ("広島県・北部" . "422")
	     ("山口県・西部" . "431")
	     ("山口県・中部" . "432")
	     ("山口県・東部" . "433")
	     ("山口県・北部" . "434")
	     ("香川県" . "441")
	     ("愛媛県・中予地方" . "451")
	     ("愛媛県・東予地方" . "452")
	     ("愛媛県・南予地方" . "453")
	     ("徳島県・北部" . "461")
	     ("徳島県・南部" . "462")
	     ("高知県・中部" . "471")
	     ("高知県・東部" . "472")
	     ("高知県・西部" . "473")
	     ("福岡県・福岡地方" . "481")
	     ("福岡県・北九州地方" . "482")
	     ("福岡県・筑豊地方" . "483")
	     ("福岡県・筑後地方" . "484")
	     ("大分県・中部" . "491")
	     ("大分県・北部" . "492")
	     ("大分県・西部" . "493")
	     ("大分県・南部" . "494")
	     ("佐賀県・南部" . "501")
	     ("佐賀県・北部" . "502")
	     ("熊本県・熊本地方" . "511")
	     ("熊本県・阿蘇地方" . "512")
	     ("熊本県・天草芦北地方" . "513")
	     ("熊本県・球磨地方" . "514")
	     ("宮崎県・南部平野" . "521")
	     ("宮崎県・南部山沿い" . "522")
	     ("宮崎県・北部平野" . "523")
	     ("宮崎県・北部山沿い" . "524")
	     ("長崎県・南部" . "531")
	     ("長崎県・北部" . "532")
	     ("長崎県・壱岐対馬地方" . "533")
	     ("長崎県・五島地方" . "534")
	     ("鹿児島県・薩摩地方" . "561")
	     ("鹿児島県・大隅地方" . "562")
	     ("鹿児島県・種子島" . "563")
	     ("鹿児島県・屋久島" . "563")
	     ("奄美諸島" . "564")
	     ("沖縄県・中南部" . "591")
	     ("沖縄県・北部" . "592")
	     ("沖縄県・久米島" . "593")
	     ("沖縄県・大東島" . "594")
	     ("沖縄県・宮古島" . "595")
	     ("沖縄県・石垣島" . "596")
	     ("沖縄県・与那国島" . "597"))))
      (mapcar (lambda (area)
		(cons (car area) (format format (cdr area))))
	      alist)))
  "Associative list of regions and urls.")

(defcustom w3m-weather-default-area
  "京都府・南部"
  "Default region to check weateher."
  :group 'w3m
  :type (cons 'radio
	      (mapcar (lambda (area) (list 'const (car area)))
		      w3m-weather-url-alist)))

(defcustom w3m-weather-filter-functions
  '(w3m-weather-remove-headers
    w3m-weather-remove-footers
    w3m-weather-remove-weather-images
    w3m-weather-remove-washing-images
    w3m-weather-remove-futon-images
    w3m-weather-remove-week-weather-images
    w3m-weather-insert-title)
  "Filter functions to remove useless tags."
  :group 'w3m
  :type 'hook)

(defconst w3m-extended-charcters-table
  '(("\xa0" . " ")))

(defconst w3m-entity-alist		; html character entities and values
  '(("nbsp" . " ")
    ("gt" . ">")
    ("lt" . "<")
    ("amp" . "&")
    ("quot" . "\"")
    ("apos" . "'")))
(defvar w3m-entity-db nil)		; nil means un-initialized
(defconst w3m-entity-db-size 13)	; size of obarray

(defvar w3m-current-url nil "URL of this buffer.")
(defvar w3m-current-title nil "Title of this buffer.")
(defvar w3m-current-forms nil "Forms of this buffer.")
(defvar w3m-url-history nil "History of URL.")
(make-variable-buffer-local 'w3m-current-url)
(make-variable-buffer-local 'w3m-current-title)
(make-variable-buffer-local 'w3m-url-history)

(defvar w3m-verbose t "Flag variable to control messages.")

(defvar w3m-cache-buffer nil)
(defvar w3m-cache-articles nil)
(defvar w3m-cache-hashtb nil)
(defvar w3m-input-url-history nil)

(defconst w3m-arrived-db-size 1023)
(defvar w3m-arrived-db nil)		; nil means un-initialized.
(defvar w3m-arrived-seq nil)
(defvar w3m-arrived-user-list nil)

(defvar w3m-process-message nil "Function to message status.")
(defvar w3m-process-user nil)
(defvar w3m-process-passwd nil)
(defvar w3m-process-user-counter 0)
(defvar w3m-process-temp-file nil)
(make-variable-buffer-local 'w3m-process-temp-file)

(defvar w3m-bookmark-data nil)
(defvar w3m-bookmark-file-time-stamp nil)
(defvar w3m-bookmark-section-history nil)
(defvar w3m-bookmark-title-history nil)

(defvar w3m-display-inline-image-status nil) ; 'on means image is displayed

(defconst w3m-image-type-alist
  '(("image/jpeg" . jpeg)
    ("image/gif" . gif)
    ("image/png" . png)
    ("image/x-xbm" . xbm)
    ("image/x-xpm" . xpm))
  "An alist of CONTENT-TYPE and IMAGE-TYPE.")

(defvar w3m-work-buffer-list nil)
(defconst w3m-work-buffer-name " *w3m-work*")

(defconst w3m-meta-content-type-charset-regexp
  (eval-when-compile
    (concat "<meta[ \t]+http-equiv=\"?Content-type\"?[ \t]+content=\"\\([^;]+\\)"
	    ";[ \t]*charset=\"?\\([^\"]+\\)\"?"
	    ">"))
  "Regexp used in parsing `<META HTTP-EQUIV=\"Content-Type\" content=\"...;charset=...\">
for a charset indication")

(defconst w3m-meta-charset-content-type-regexp
  (eval-when-compile
    (concat "<meta[ \t]+content=\"\\([^;]+\\)"
	    ";[ \t]*charset=\"?\\([^\"]+\\)\"?"
	    "[ \t]+http-equiv=\"?Content-type\"?>"))
  "Regexp used in parsing `<META content=\"...;charset=...\" HTTP-EQUIV=\"Content-Type\">
for a charset indication")

(eval-and-compile
  (defconst w3m-form-string-regexp
    "\\(\"\\(\\([^\"\\\\]+\\|\\\\.\\)+\\)\"\\|[^\"<> \t\r\f\n]*\\)"
    "Regexp used in parsing to detect string."))

(defconst w3m-command-arguments
  '("-T" "text/html" "-t" tab-width "-halfdump"
    "-cols" (if (< 0 w3m-fill-column)
		w3m-fill-column		; fixed columns
	      (+ (frame-width) (or w3m-fill-column -1)))) ; fit for frame
  "Arguments for execution of w3m.")

(defsubst w3m-anchor (&optional point)
  (get-text-property (or point (point)) 'w3m-href-anchor))

(defsubst w3m-image (&optional point)
  (get-text-property (or point (point)) 'w3m-image))
 
(defsubst w3m-action (&optional point)
  (get-text-property (or point (point)) 'w3m-action))

(defun w3m-message (&rest args)
  "Alternative function of `message' for w3m.el."
  (if w3m-verbose
      (apply (function message) args)
    (apply (function format) args)))

(defun w3m-sub-list (list n)
  "Make new list from LIST with top most N items.
If N is negative, last N items of LIST is returned."
  (if (< n 0)
      ;; N is negative, get items from tail of list
      (if (>= (- n) (length list))
	  (copy-sequence list)
	(nthcdr (+ (length list) n) (copy-sequence list)))
    ;; N is non-negative, get items from top of list
    (if (>= n (length list))
	(copy-sequence list)
      (nreverse (nthcdr (- (length list) n) (reverse list))))))

(defun w3m-load-list (file coding)
  "Load list from FILE with CODING and return list."
  (when (file-readable-p file)
    (with-temp-buffer
      (let ((file-coding-system-for-read coding)
	    (coding-system-for-read coding))
	(insert-file-contents file)
	(condition-case nil
	    (read (current-buffer))	; return value
	  (error nil))))))

(defun w3m-save-list (file coding list)
  "Save LIST into file with CODING."
  (when (and list (file-writable-p file))
    (with-temp-buffer
      (let ((file-coding-system coding)
	    (coding-system-for-write coding))
	(print list (current-buffer))
	(write-region (point-min) (point-max)
		      file nil 'nomsg)))))

(defsubst w3m-arrived-p (url)
  "If URL has been arrived, return non-nil value.  Otherwise return nil."
  (intern-soft url w3m-arrived-db))

(defsubst w3m-arrived-add (url)
  "Add URL to hash database of arrived URLs."
  (when (> (length url) 5) ;; ignore short
    (set-text-properties 0 (length url) nil url)
    (put (intern url w3m-arrived-db)
	 'w3m-arrived-seq
	 (setq w3m-arrived-seq (1+ w3m-arrived-seq)))))

(defun w3m-arrived-setup ()
  "Load arrived url list from 'w3m-arrived-file' and setup hash database."
  (unless w3m-arrived-db
    (setq w3m-arrived-db (make-vector w3m-arrived-db-size nil)
	  w3m-arrived-seq 0)
    (let ((list (w3m-load-list w3m-arrived-file
			       w3m-arrived-file-coding-system)))
      (dolist (url list) (w3m-arrived-add url))
      (unless w3m-input-url-history
	(setq w3m-input-url-history list)))))

(defun w3m-arrived-shutdown ()
  "Save hash database of arrived URLs to 'w3m-arrived-file'."
  (when w3m-arrived-db
    (let (list)
      (mapatoms (lambda (sym)
		  (when sym
		    (setq list
			  (cons (cons (symbol-name sym)
				      (get sym 'w3m-arrived-seq))
				list))))
		w3m-arrived-db)
      (w3m-save-list w3m-arrived-file
		     w3m-arrived-file-coding-system
		     (mapcar
		      (function car)
		      (sort list
			    (lambda (a b) (> (cdr a) (cdr b)))))))
    (setq w3m-arrived-db nil)))
(add-hook 'kill-emacs-hook 'w3m-arrived-shutdown)

(defun w3m-arrived-store-position (url &optional point window-start)
  (when (stringp url)
    (let ((ident (intern-soft url w3m-arrived-db)))
      (when ident
	(set ident (cons (or window-start (window-start))
			 (or point (point))))))))

(defun w3m-arrived-restore-position (url)
  (let ((ident (intern-soft url w3m-arrived-db)))
    (when (and ident (boundp ident))
      (set-window-start nil (car (symbol-value ident)))
      (goto-char (cdr (symbol-value ident))))))


;;; Working buffers:
(defsubst w3m-get-buffer-create (name)
  "Return the buffer named NAME, or create such a buffer and return it."
  (or (get-buffer name)
      (let ((buf (get-buffer-create name)))
	(setq w3m-work-buffer-list (cons buf w3m-work-buffer-list))
	(buffer-disable-undo buf)
	buf)))

(put 'w3m-with-work-buffer 'lisp-indent-function 0)
(put 'w3m-with-work-buffer 'edebug-form-spec '(&rest body))
(defmacro w3m-with-work-buffer (&rest body)
  "Execute the forms in BODY with working buffer as the current buffer."
  (` (with-current-buffer
	 (w3m-get-buffer-create w3m-work-buffer-name)
       (,@ body))))

(defun w3m-kill-all-buffer ()
  "Kill all working buffer."
  (dolist (buf w3m-work-buffer-list)
    (when (buffer-live-p buf)
      (kill-buffer buf)))
  (setq w3m-work-buffer-list nil))


;;; Form:
(defun w3m-form-new (method action &optional baseurl)
  "Return new form object."
  (vector 'w3m-form-object
	  (if (stringp method)
	      (intern method)
	    method)
	  (if baseurl
	      (w3m-expand-url action baseurl)
	    action)
	  nil))

(defsubst w3m-form-p (obj)
  "Return t if OBJ is a form object."
  (and (vectorp obj)
       (symbolp (aref 0 obj))
       (eq (aref 0 obj) 'w3m-form-object)))

(defmacro w3m-form-method (form)
  `(aref ,form 1))
(defmacro w3m-form-action (form)
  `(aref ,form 2))
(defmacro w3m-form-plist (form)
  `(aref ,form 3))
(defmacro w3m-form-put (form name value)
  (let ((tempvar (make-symbol "formobj")))
    `(let ((,tempvar ,form))
       (aset ,tempvar 3 (plist-put (w3m-form-plist ,tempvar) (intern ,name) ,value)))))
(defmacro w3m-form-get (form name)
  `(plist-get (w3m-form-plist ,form) (intern ,name)))

(defun w3m-url-encode-string (str &optional coding)
  (apply (function concat)
	 (mapcar
	  (lambda (ch)
	    (cond
	     ((string-match "[-a-zA-Z0-9_:/]" (char-to-string ch)) ; xxx?
	      (char-to-string ch))	; printable
	     (t
	      (format "%%%02X" ch))))	; escape
	  (string-to-list
	   (encode-coding-string
	    str
	    (or coding
		(w3m-static-if (boundp 'MULE)
		    '*iso-2022-jp*
		  'iso-2022-7bit)))))))

(defun w3m-form-make-get-string (form)
  (when (eq 'get (w3m-form-method form))
    (let ((plist (w3m-form-plist form))
	  (buf))
      (while plist
	(setq buf (cons
		   (format "%s=%s"
			   (w3m-url-encode-string (symbol-name (car plist)))
			   (w3m-url-encode-string (nth 1 plist)))
		   buf)
	      plist (nthcdr 2 plist)))
      (if buf
	  (format "%s?%s"
		  (w3m-form-action form)
		  (mapconcat (function identity) buf "&"))
	(w3m-form-action form)))))

(put 'w3m-parse-attributes 'lisp-indent-function '1)
(put 'w3m-parse-attributes 'edebug-form-spec '(&rest form))
(defmacro w3m-parse-attributes (attributes &rest form)
  (` (let ((,@ (mapcar
		(lambda (attr)
		  (if (listp attr) (car attr) attr))
		attributes)))
       (while
	   (cond
	    (,@ (mapcar
		 (lambda (attr)
		   (or (symbolp attr)
		       (and (listp attr)
			    (<= (length attr) 2)
			    (symbolp (car attr)))
		       (error "Internal error, type mismatch."))
		   (let ((sexp (quote
				(or (match-string 2)
				    (match-string 1)))))
		     (when (listp attr)
		       (cond
			((eq (nth 1 attr) :case-ignore)
			 (setq sexp
			       (quote
				(downcase
				 (or (match-string 2)
				     (match-string 1))))))
			((eq (nth 1 attr) :integer)
			 (setq sexp
			       (quote
				(string-to-number
				 (or (match-string 2)
				     (match-string 1))))))
			((nth 1 attr)
			 (error "Internal error, unknown modifier.")))
		       (setq attr (car attr)))
		     (` ((looking-at
			  (, (format "%s=%s"
				     (symbol-name attr)
				     w3m-form-string-regexp)))
			 (setq (, attr) (, sexp))))))
		 attributes))
	    ((looking-at
	      (, (concat "[A-z]*=" w3m-form-string-regexp))))
	    ((looking-at "[^<> \t\r\f\n]+")))
	 (goto-char (match-end 0))
	 (skip-chars-forward " \t\r\f\n"))
       (skip-chars-forward "^>")
       (,@ form))))

(defun w3m-form-parse-region (start end)
  "Parse HTML data in this buffer and return form objects."
  (save-restriction
    (narrow-to-region start end)
    (let ((case-fold-search t)
	  forms)
      (goto-char (point-min))
      (while (re-search-forward "<\\(\\(form\\)\\|\\(input\\)\\|select\\)[ \t\r\f\n]+" nil t)
	(cond
	 ((match-string 2)
	  ;; When <FORM> is found.
	  (w3m-parse-attributes (action (method :case-ignore))
	    (setq forms
		  (cons (w3m-form-new (or method "get")
				      (or action w3m-current-url)
				      w3m-current-url)
			forms))))
	 ((match-string 3)
	  ;; When <INPUT> is found.
	  (w3m-parse-attributes (name value (type :case-ignore))
	    (when name
	      (w3m-form-put (car forms)
			    name
			    (cons value (w3m-form-get (car forms) name))))))
	 ;; When <SELECT> is found.
	 (t
	  ;; FIXME: この部分では、更に <OPTION> タグを処理して、後から
	  ;; 利用できるように値のリストを作成し、保存しておく必要があ
	  ;; る。しかし、これを実装するのは、まっとうな HTML parser を
	  ;; 実装するのに等しい労力が必要であるので、今回は手抜きして
	  ;; おく。
	  )))
      (set (make-local-variable 'w3m-current-forms) (nreverse forms)))))

(defun w3m-fontify-forms ()
  "Process half-dumped data in this buffer and fontify <input_alt> tags."
  (goto-char (point-min))
  (while (search-forward "<input_alt " nil t)
    (let (start)
      (setq start (match-beginning 0))
      (goto-char (match-end 0))
      (w3m-parse-attributes ((fid :integer)
			     (type :case-ignore)
			     (width :integer)
			     (maxlength :integer)
			     name value)
	(search-forward "</input_alt>")
	(goto-char (match-end 0))
	(let ((form (nth fid w3m-current-forms)))
	  (when form
	    (cond
	     ((string= type "submit")
	      (put-text-property start (point)
				 'w3m-action
				 `(w3m-form-submit ,form)))
	     ((string= type "reset")
	      (put-text-property start (point)
				 'w3m-action
				 `(w3m-form-reset ,form)))
	     (t ;; input button.
	      (put-text-property start (point)
				 'w3m-action
				 `(w3m-form-input ,form
						  ,name
						  ,type
						  ,width
						  ,maxlength
						  ,value))
	      (w3m-form-put form name value)))
	    (put-text-property start (point) 'face 'w3m-form-face))
	  )))))

(defun w3m-form-replace (string)
  (let* ((start (text-property-any
		 (point-min)
		 (point-max)
		 'w3m-action
		 (get-text-property (point) 'w3m-action)))
	 (width (string-width
		 (buffer-substring
		  start
		  (next-single-property-change start 'w3m-action))))
	 (prop (text-properties-at start))
	 (buffer-read-only))
    (goto-char start)
    (insert (setq string (truncate-string string width))
	    (make-string (- width (string-width string)) ?\ ))
    (delete-region (point)
		   (next-single-property-change (point) 'w3m-action))
    (add-text-properties start (point) prop)
    (point)))

;;; FIXME: 本当は type の値に合わせて、適切な値のみを受け付けるように
;;; チェックしたり、入力方法を変えたりするような実装が必要。
(defun w3m-form-input (form name type width maxlength value)
  (save-excursion
    (let ((input (read-from-minibuffer
		  (concat (upcase type) ":")
		  (w3m-form-get form name))))
      (w3m-form-put form name input)
      (w3m-form-replace input))))

(defun w3m-form-submit (form)
  (let ((url (w3m-form-make-get-string form)))
    (if url
	(w3m-goto-url url)
      (w3m-message "This form's method has not been supported: %s"
		   (prin1-to-string (w3m-form-method form))))))

(defsubst w3m-form-real-reset (form sexp)
  (and (eq 'w3m-form-input (car sexp))
       (eq form (nth 1 sexp))
       (w3m-form-put form (nth 2 sexp) (nth 6 sexp))
       (w3m-form-replace (nth 6 sexp))))

(defun w3m-form-reset (form)
  (save-excursion
    (let (pos prop)
      (when (setq prop (get-text-property
			(goto-char (point-min))
			'w3m-action))
	(goto-char (or (w3m-form-real-reset form prop)
		       (next-single-property-change pos 'w3m-action))))
      (while (setq pos (next-single-property-change (point) 'w3m-action))
	(goto-char pos)
	(goto-char (or (w3m-form-real-reset form (get-text-property pos 'w3m-action))
		       (next-single-property-change pos 'w3m-action)))))))


;;; HTML character entity handling:

(defun w3m-entity-db-setup ()
  ;; initialize entity database (obarray)
  (setq w3m-entity-db (make-vector w3m-entity-db-size 0))
  (dolist (elem w3m-entity-alist)
    (set (intern (car elem) w3m-entity-db)
	 (cdr elem))))

(defun w3m-entity-value (name)
  ;; initialize if need
  (if (null w3m-entity-db)
      (w3m-entity-db-setup))
    ;; return value of specified entity, or empty string for unknown entity.
    (or (symbol-value (intern-soft (match-string 1) w3m-entity-db))
	(if (not (char-equal (string-to-char name) ?#))
	    (concat "&" name)		; unknown entity
	  ;; case of immediate character (accept only 0x20 .. 0x7e)
	  (let ((char (string-to-int (substring name 1)))
		sym)
	    ;; make character's representation with learning
	    (set (setq sym (intern name w3m-entity-db))
		 (if (or (< char 32) (< 127 char))
		     "~"		; un-supported character
		   (char-to-string char)))))))

(defun w3m-fontify-bold ()
  "Fontify bold characters in this buffer which contains half-dumped data."
  (goto-char (point-min))
  (while (search-forward "<b>" nil t)
    (let ((start (match-beginning 0)))
      (delete-region start (match-end 0))
      (when (search-forward "</b>" nil t)
	(delete-region (match-beginning 0) (match-end 0))
	(put-text-property start (match-beginning 0) 'face 'bold)))))

(defun w3m-fontify-underline ()
  "Fontify underline characters in this buffer which contains half-dumped data."
  (goto-char (point-min))
  (while (search-forward "<u>" nil t)
    (let ((start (match-beginning 0)))
      (delete-region start (match-end 0))
      (when (search-forward "</u>" nil t)
	(delete-region (match-beginning 0) (match-end 0))
	(put-text-property start (match-beginning 0) 'face 'underline)))))

(defun w3m-fontify-anchors ()
  "Fontify anchor tags in this buffer which contains half-dumped data."
  ;; Delete excessive `hseq' elements of anchor tags.
  (goto-char (point-min))
  (while (re-search-forward "<a\\( hseq=\"[-0-9]+\"\\)" nil t)
    (delete-region (match-beginning 1) (match-end 1)))
  ;; Re-ordering anchor elements.
  (goto-char (point-min))
  (let (href)
    (while (re-search-forward "<a\\([ \t\n]\\)[^>]+[ \t\n]href=\\([\"']?[^\"' >]*[\"']?\\)" nil t)
      (setq href (buffer-substring (match-beginning 2) (match-end 2)))
      (delete-region (match-beginning 2) (match-end 2))
      (goto-char (match-beginning 1))
      (insert " href=" href)))
  ;; Fontify anchor tags.
  (goto-char (point-min))
  (while (re-search-forward
	  "<a\\([ \t\n]+href=[\"']?\\([^\"' >]*\\)[\"']?\\)?\\([ \t\n]+name=\"?\\([^\" >]*\\)\"?\\)?[^>]*>"
	  nil t)
    (let ((url (match-string 2))
	  (tag (match-string 4))
	  (start (match-beginning 0))
	  (end))
      (delete-region start (match-end 0))
      (cond (url
	     (when (search-forward "</a>" nil t)
	       (setq url (w3m-expand-url url w3m-current-url))
	       (delete-region (setq end (match-beginning 0)) (match-end 0))
	       (put-text-property start end 'face
				  (if (w3m-arrived-p url)
				      'w3m-arrived-anchor-face
				    'w3m-anchor-face))
	       (put-text-property start end 'w3m-href-anchor url)
	       (put-text-property start end 'mouse-face 'highlight))
	     (when tag
	       (put-text-property start end 'w3m-name-anchor tag)))
	    (tag
	     (when (re-search-forward "<\\|\n" nil t)
	       (setq end (match-beginning 0))
	       (put-text-property start end 'w3m-name-anchor tag)))))))

(w3m-static-if (and (not (featurep 'xemacs))
		    (>= emacs-major-version 21)) (progn    
(defun w3m-create-image (url &optional no-cache)
  "Retrieve data from URL and create an image object.
If optional argument NO-CACHE is non-nil, cache is not used."
  (let ((type (w3m-retrieve url 'raw nil no-cache)))
    (when type
      (w3m-with-work-buffer
	(create-image (buffer-string) 
		      (cdr (assoc type w3m-image-type-alist))
		      t
		      :ascent 'center)))))

(defun w3m-insert-image (beg end image)
  "Display image on the current buffer.
Buffer string between BEG and END are replaced with IMAGE."
  (add-text-properties beg end
		       (list 'display image
			     'intangible image
			     'invisible nil)))

(defun w3m-remove-image (beg end)
  "Remove an image which is inserted between BEG and END."
  (remove-text-properties beg end '(display intangible)))
;; end of Emacs 21 definition.
)
(w3m-static-if (featurep 'xemacs) (progn
(defun w3m-create-image (url &optional no-cache)
  "Retrieve data from URL and create an image object.
If optional argument NO-CACHE is non-nil, cache is not used."
  (let ((type (w3m-retrieve url 'raw nil no-cache)))
    (when type
      (let ((data (w3m-with-work-buffer (buffer-string))))
	(make-glyph
	 (make-image-instance
	  (vector (or (cdr (assoc type w3m-image-type-alist))
		      'autodetect)
		  :data data)
	  nil nil 'no-error))))))

(defun w3m-insert-image (beg end image)
  "Display image on the current buffer.
Buffer string between BEG and END are replaced with IMAGE."
  (let (extent glyphs)
    (while (setq extent (extent-at beg nil 'w3m-xmas-icon extent 'at))
      (setq glyphs (cons (extent-end-glyph extent) glyphs)))
    (setq extent (make-extent beg end))
    (set-extent-property extent 'invisible t)
    (set-extent-property extent 'w3m-xmas-icon t)
    (set-extent-end-glyph extent image)
    (while glyphs
      (setq extent (make-extent (point)(point)))
      (set-extent-property extent 'w3m-xmas-icon t)
      (set-extent-end-glyph extent (car glyphs))
      (setq glyphs (cdr glyphs)))))

(defun w3m-remove-image (beg end)
  "Remove an image which is inserted between BEG and END."
  (let (extent)
    (while (setq extent (extent-at beg nil 'w3m-xmas-icon extent 'at))
      (if (extent-end-glyph extent)
	  (set-extent-end-glyph extent nil))
      (set-extent-property extent 'invisible nil))
    (while (setq extent (extent-at end nil 'w3m-xmas-icon extent 'at))
      (if (extent-end-glyph extent)
	  (set-extent-end-glyph extent nil))
      (set-extent-property extent 'invisible nil))))

;; end of XEmacs definition.
)
(defun w3m-create-image (url &optional no-cache))
(defun w3m-insert-image (beg end image))
;; end of w3m-static-if
))

(defun w3m-fontify-images ()
  "Fontify image alternate strings in this buffer which contains half-dumped data."
  (goto-char (point-min))
  (while (re-search-forward "<\\(img_alt\\) src=\"\\([^\"]*\\)\">" nil t)
    (let ((src (match-string 2))
	  (upper (string= (match-string 1) "IMG_ALT"))
	  (start (match-beginning 0))
	  (end))
      (delete-region start (match-end 0))
      (setq src (w3m-expand-url src w3m-current-url))
      (when (search-forward "</img_alt>" nil t)
	(delete-region (setq end (match-beginning 0)) (match-end 0))
	(put-text-property start end 'face 'w3m-image-face)
	(put-text-property start end 'w3m-image src)
	(if upper (put-text-property start end 'w3m-image-redundant t))
	(put-text-property start end 'mouse-face 'highlight)))))

(defun w3m-toggle-inline-images (&optional force no-cache)
  "Toggle displaying of inline images on current buffer.
If optional argument FORCE is non-nil, displaying is forced.
If second optional argument NO-CACHE is non-nil, cache is not used."
  (interactive "P")
  (unless (and force (eq w3m-display-inline-image-status 'on))
    (let ((cur-point (point)) 
	  (buffer-read-only)
	  point end url image)
      (if (or force (eq w3m-display-inline-image-status 'off))
	  (save-excursion
	    (goto-char (point-min))
	    (while (if (get-text-property (point) 'w3m-image)
		       (setq point (point))
		     (setq point (next-single-property-change (point)
							      'w3m-image)))
	      (setq end (or (next-single-property-change point 'w3m-image)
			    (point-max)))
	      (goto-char end)
	      (if (setq url (w3m-image point))
		  (setq url (w3m-expand-url url w3m-current-url)))
	      (if (get-text-property point 'w3m-image-redundant)
		  (progn
		    ;; Insert dummy string instead of redundant image.
		    (setq image
			  (make-string
			   (string-width (buffer-substring point end))
			   ? ))
		    (put-text-property point end 'invisible t)
		    (setq point (point))
		    (insert image)
		    (put-text-property point (point) 'w3m-image-dummy t)
		    (put-text-property point (point) 'w3m-image "dummy"))
		(when (and url
			   (setq image (w3m-create-image url no-cache)))
		  (w3m-insert-image point end image)
		  ;; Redisplay
		  (save-excursion
		    (goto-char cur-point)
		    (sit-for 0)))))
	    (setq w3m-display-inline-image-status 'on))
	(save-excursion
	  (goto-char (point-min))
	  (while (if (get-text-property (point) 'w3m-image)
		     (setq point (point))
		   (setq point (next-single-property-change (point)
							    'w3m-image)))
	    (setq end (or (next-single-property-change point 'w3m-image)
			  (point-max)))
	    (goto-char end)
	    ;; IMAGE-ALT-STRING DUMMY-STRING
	    ;; <--------w3m-image---------->
	    ;; <---redundant--><---dummy--->
	    ;; <---invisible-->
	    (cond
	     ((get-text-property point 'w3m-image-redundant)
	      ;; Remove invisible property.
	      (remove-text-properties point end '(invisible)))
	     ((get-text-property point 'w3m-image-dummy)
	      ;; Remove dummy string.
	      (delete-region point end))
	     (t (w3m-remove-image point end))))
	  (setq w3m-display-inline-image-status 'off))))))

(defun w3m-fontify ()
  "Fontify this buffer."
  (let ((case-fold-search t)
	(buffer-read-only))
    (run-hooks 'w3m-fontify-before-hook)
    ;; Delete <?xml ... ?> tag
    (goto-char (point-min))
    (if (search-forward "<?xml" nil t)
	(let ((start (match-beginning 0)))
	  (search-forward "?>" nil t)
	  (delete-region start (match-end 0))))
    ;; Delete extra title tag.
    (goto-char (point-min))
    (let (start)
      (and (search-forward "<title>" nil t)
	   (setq start (match-beginning 0))
	   (search-forward "</title>" nil t)
	   (delete-region start (match-end 0))))
    (w3m-fontify-bold)
    (w3m-fontify-underline)
    (w3m-fontify-anchors)
    (if w3m-use-form
	(w3m-fontify-forms))
    (w3m-fontify-images)
    ;; Remove other markups.
    (goto-char (point-min))
    (while (re-search-forward "</?[A-z_][^>]*>" nil t)
      (delete-region (match-beginning 0) (match-end 0)))
    ;; Decode escaped characters (entities).
    (goto-char (point-min))
    (let (prop)
      (while (re-search-forward "&\\([a-z]+\\|#[0-9]+\\);?" nil t)
	(setq prop (text-properties-at (match-beginning 0)))
	(replace-match (w3m-entity-value (match-string 1)) nil t)
	(if prop (add-text-properties (match-beginning 0) (point) prop))))
    ;; Decode w3m-specific extended charcters.
    (let ((x (w3m-static-if (boundp 'MULE)
		 mc-flag
	       enable-multibyte-characters)))
      (set-buffer-multibyte nil)
      (dolist (elem w3m-extended-charcters-table)
	(goto-char (point-min))
	(while (search-forward (car elem) nil t)
	  (delete-region (match-beginning 0) (match-end 0))
	  (insert (cdr elem))))
      (set-buffer-multibyte x))
    (goto-char (point-min))
    (if w3m-delete-duplicated-empty-lines
	(while (re-search-forward "^[ \t]*\n\\([ \t]*\n\\)+" nil t)
	  (replace-match "\n" nil t)))
    (run-hooks 'w3m-fontify-after-hook)))

;;

(defun w3m-refontify-anchor (&optional buff)
  "Change face 'w3m-anchor-face to 'w3m-arrived-anchor-face."
  (save-excursion
    (and buff (set-buffer buff))
    (when (and (eq major-mode 'w3m-mode)
	       (eq (get-text-property (point) 'face) 'w3m-anchor-face))
      (let* ((start)
	     (end (next-single-property-change (point) 'face))
	     (buffer-read-only))
	(when (and end
		   (setq start (previous-single-property-change end 'face)))
	  (put-text-property start end 'face 'w3m-arrived-anchor-face))
	(set-buffer-modified-p nil)))))

(defun w3m-input-url (&optional prompt default)
  "Read a URL from the minibuffer, prompting with string PROMPT."
  (let (url candidates)
    (w3m-arrived-setup)
    (mapatoms (lambda (x)
		(setq candidates (cons (cons (symbol-name x) x) candidates)))
	      w3m-arrived-db)
    (setq default (or default (thing-at-point 'url)))
    (setq url (completing-read (or prompt
				   (if default
				       "URL: "
				     (format "URL (default %s): " w3m-home-page)))
			       candidates nil nil default
			       'w3m-input-url-history))
    (if (string= "" url) (setq url w3m-home-page))
    ;; remove duplication
    (setq w3m-input-url-history (cons url (delete url w3m-input-url-history)))
    ;; return value
    url))


;;; Cache:
(defun w3m-cache-setup ()
  "Initialize cache variables."
  (unless (and (bufferp w3m-cache-buffer)
	       (buffer-live-p w3m-cache-buffer))
    (save-excursion
      (set-buffer (w3m-get-buffer-create " *w3m cache*"))
      (buffer-disable-undo)
      (set-buffer-multibyte nil)
      (setq buffer-read-only t
	    w3m-cache-buffer (current-buffer)
	    w3m-cache-hashtb (make-vector 1021 0)))))

(defun w3m-cache-shutdown ()
  "Clear all cache variables and buffers."
  (when (buffer-live-p w3m-cache-buffer)
    (kill-buffer w3m-cache-buffer))
  (setq w3m-cache-hashtb nil
	w3m-cache-articles nil))

(defun w3m-cache-header (url header)
  "Store up URL's HEADER in cache."
  (w3m-cache-setup)
  (set (intern url w3m-cache-hashtb) header))

(defun w3m-cache-request-header (url)
  "Return the URL's header string, when it is stored in cache."
  (w3m-cache-setup)
  (let ((ident (intern url w3m-cache-hashtb)))
    (and (boundp ident)
	 (symbol-value ident))))

(defun w3m-cache-remove-oldest ()
  (save-excursion
    (set-buffer w3m-cache-buffer)
    (goto-char (point-min))
    (unless (zerop (buffer-size))
      (let ((ident (get-text-property (point) 'w3m-cache))
	    buffer-read-only)
	;; Remove the ident from the list of articles.
	(when ident
	  (setq w3m-cache-articles (delq ident w3m-cache-articles)))
	;; Delete the article itself.
	(delete-region (point)
		       (next-single-property-change
			(1+ (point)) 'w3m-cache nil (point-max)))))))

(defun w3m-cache-remove (url)
  "Remove URL's data from the cache."
  (w3m-cache-setup)
  (let ((ident (intern url w3m-cache-hashtb))
	beg end)
    (when (memq ident w3m-cache-articles)
      ;; It was in the cache.
      (save-excursion
	(set-buffer w3m-cache-buffer)
	(let (buffer-read-only)
	  (when (setq beg (text-property-any
			   (point-min) (point-max) 'w3m-cache ident))
	    ;; Find the end (i. e., the beginning of the next article).
	    (setq end (next-single-property-change
		       (1+ beg) 'w3m-cache (current-buffer) (point-max)))
	    (delete-region beg end)))
	(setq w3m-cache-articles (delq ident w3m-cache-articles))))))

(defun w3m-cache-contents (url buffer)
  "Store URL's contents which is placed in the BUFFER.
Return symbol to identify its cache data."
  (w3m-cache-setup)
  (let ((ident (intern url w3m-cache-hashtb)))
    (w3m-cache-remove url)
    ;; Remove the oldest article, if necessary.
    (and (numberp w3m-keep-cache-size)
	 (>= (length w3m-cache-articles) w3m-keep-cache-size)
	 (w3m-cache-remove-oldest))
    ;; Insert the new article.
    (save-excursion
      (set-buffer w3m-cache-buffer)
      (let (buffer-read-only)
	(goto-char (point-max))
	(unless (bolp) (insert "\n"))
	(let ((b (point)))
	  (insert-buffer-substring buffer)
	  ;; Tag the beginning of the article with the ident.
	  (when (> (point-max) b)
	    (put-text-property b (1+ b) 'w3m-cache ident)
	    (setq w3m-cache-articles (cons ident w3m-cache-articles))
	    ident))))))

(defun w3m-cache-request-contents (url &optional buffer)
  "Insert URL's data to the BUFFER.
If URL's data is found in the cache, return t.  Otherwise return nil.
When BUFFER is nil, all data will be inserted in the current buffer."
  (w3m-cache-setup)
  (let ((ident (intern url w3m-cache-hashtb)))
    (when (memq ident w3m-cache-articles)
      ;; It was in the cache.
      (let (beg end type charset)
	(save-excursion
	  (set-buffer w3m-cache-buffer)
	  (if (setq beg (text-property-any
			 (point-min) (point-max) 'w3m-cache ident))
	      ;; Find the end (i. e., the beginning of the next article).
	      (setq end (next-single-property-change
			 (1+ beg) 'w3m-cache (current-buffer) (point-max)))
	    ;; It wasn't in the cache after all.
	    (setq w3m-cache-articles (delq ident w3m-cache-articles))))
	(and beg
	     end
	     (save-excursion
	       (when buffer
		 (set-buffer buffer))
	       (let (buffer-read-only)
		 (insert-buffer-substring w3m-cache-buffer beg end))
	       t))))))


;;; Handle process:
(defun w3m-exec-process (&rest args)
  (save-excursion
    (let ((coding-system-for-read
	   (w3m-static-if (boundp 'MULE) '*noconv* 'binary))
	  (coding-system-for-write w3m-coding-system)
	  (default-process-coding-system
	    (cons (w3m-static-if (boundp 'MULE) '*noconv* 'binary)
		  w3m-coding-system))
	  (process-connection-type w3m-process-connection-type))
      (if w3m-async-exec
	  ;; start-process
	  (let ((w3m-process-user)
		(w3m-process-passwd)
		(w3m-process-user-counter 2)
		(proc (apply 'start-process w3m-command (current-buffer) w3m-command args)))
	    (set-process-filter proc 'w3m-exec-filter)
	    (set-process-sentinel proc (lambda (proc event) nil))
	    (process-kill-without-query proc)
	    (while (eq (process-status proc) 'run)
	      (if (functionp w3m-process-message)
		  (funcall w3m-process-message))
	      (sit-for 0.2)
	      (discard-input))
	    (and w3m-current-url
		 w3m-process-user
		 (setq w3m-arrived-user-list
		       (cons
			(cons w3m-current-url
			      (list w3m-process-user w3m-process-passwd))
			(delete (assoc w3m-current-url w3m-arrived-user-list)
				w3m-arrived-user-list)))))
	;; call-process
	(apply 'call-process w3m-command nil t nil args)))))

(defun w3m-exec-get-user (url)
  (if (= w3m-process-user-counter 0)
      nil
    (catch 'get
      (dolist (elem w3m-arrived-user-list nil)
	(when (string-match (concat "^" (regexp-quote (car elem))) url)
	  (setq w3m-process-user-counter (1- w3m-process-user-counter))
	  (throw 'get (cdr elem)))))))

(defun w3m-read-file-name (&optional prompt dir default existing initial)
  (let* ((default (and default (file-name-nondirectory default)))
	 (prompt (or prompt
		     (if default (format "Save to (%s): " default) "Save to: ")))
	 (initial (or initial default))
	 (dir (file-name-as-directory (or dir w3m-default-save-directory)))
	 (default-directory dir)
	 (file (read-file-name prompt dir default existing initial)))
    (if (not (file-directory-p file))
	(setq w3m-default-save-directory
	      (or (file-name-directory file) w3m-default-save-directory))
      (setq w3m-default-save-directory file)
      (if default
	  (setq file (expand-file-name default file))))
    (expand-file-name file)))

(defun w3m-read-passwd (prompt)
  (let ((inhibit-input-event-recording t))
    (if (fboundp 'read-passwd)
	(condition-case nil
	    (read-passwd prompt)
	  (error ""))
      (let ((pass "")
	    (c 0)
	    (echo-keystrokes 0)
	    (ociea cursor-in-echo-area))
	(condition-case nil
	    (progn
	      (setq cursor-in-echo-area 1)
	      (while (and (/= c ?\r) (/= c ?\n) (/= c ?\e) (/= c 7)) ;; ^G
		(message "%s%s"
			 prompt
			 (make-string (length pass) ?.))
		(setq c (read-char-exclusive))
		(cond
		 ((char-equal c ?\C-u)
		  (setq pass ""))
		 ((or (char-equal c ?\b) (char-equal c ?\177))  ;; BS DELL
		  ;; delete one character in the end
		  (if (not (equal pass ""))
		      (setq pass (substring pass 0 -1))))
		 ((< c 32) ()) ;; control, just ignore
		 (t
		  (setq pass (concat pass (char-to-string c))))))
	      (setq cursor-in-echo-area -1))
	  (quit
	   (setq cursor-in-echo-area ociea)
	   (signal 'quit nil))
	  (error
	   ;; Probably not happen. Just align to the code above.
	   (setq pass "")))
	(setq cursor-in-echo-area ociea)
	(message "")
	(sit-for 0)
	pass))))

(defun w3m-exec-filter (process string)
  (if (buffer-name (process-buffer process))
      (with-current-buffer (process-buffer process)
	(let ((buffer-read-only nil)
	      (case-fold-search nil))
	  (goto-char (process-mark process))
	  (insert string)
	  (set-marker (process-mark process) (point))
	  (unless (string= "" string)
	    (goto-char (point-min))
	    (cond
	     ((and (looking-at
		    "\\(\nWrong username or password\n\\)?Username: Password: ")
		   (= (match-end 0) (point-max)))
	      (setq w3m-process-passwd
		    (or (nth 1 (w3m-exec-get-user w3m-current-url))
			(w3m-read-passwd "Password: ")))
	      (condition-case nil
		  (progn
		    (process-send-string process
					 (concat w3m-process-passwd "\n"))
		    (delete-region (point-min) (point-max)))
		(error nil)))
	     ((and (looking-at
		    "\\(\nWrong username or password\n\\)?Username: ")
		   (= (match-end 0) (point-max)))
	      (setq w3m-process-user
		    (or (nth 0 (w3m-exec-get-user w3m-current-url))
			(read-from-minibuffer "Username: ")))
	      (condition-case nil
		  (process-send-string process
				       (concat w3m-process-user "\n"))
		(error nil)))))))))


;;; Handle character sets:
(defun w3m-charset-to-coding-system (charset)
  "Return coding-system corresponding with CHARSET.
CHARSET is a symbol whose name is MIME charset.
This function is imported from mcharset.el."
  (if (stringp charset)
      (setq charset (intern (downcase charset))))
  (let ((cs (assq charset w3m-charset-coding-system-alist)))
    (setq cs (if cs (cdr cs) charset))
    (if (find-coding-system cs)
	cs)))

(defun w3m-decode-buffer (type charset)
  (if (and (not charset) (string= type "text/html"))
      (setq charset
	    (let ((case-fold-search t))
	      (goto-char (point-min))
	      (and (or (re-search-forward
			w3m-meta-content-type-charset-regexp nil t)
		       (re-search-forward
			w3m-meta-charset-content-type-regexp nil t))
		   (buffer-substring-no-properties (match-beginning 2)
						   (match-end 2))))))
  (decode-coding-region
   (point-min) (point-max)
   (if charset
       (w3m-charset-to-coding-system charset)
     (let ((default (condition-case nil
			(coding-system-category w3m-coding-system)
		      (error nil)))
	   (candidate (detect-coding-region (point-min) (point-max))))
       (unless (listp candidate)
	 (setq candidate (list candidate)))
       (catch 'coding
	 (dolist (coding candidate)
	   (if (eq default (coding-system-category coding))
	       (throw 'coding coding)))
	 (if (eq (coding-system-category 'binary)
		 (coding-system-category (car candidate)))
	     w3m-coding-system
	   (car candidate))))))
  (set-buffer-multibyte t))


;;; Retrieve local data:
(defun w3m-local-content-type (url)
  (catch 'type-detected
    (dolist (elem w3m-content-type-alist "unknown")
      (if (string-match (nth 1 elem) url)
	  (throw 'type-detected (car elem))))))

(defun w3m-local-retrieve (url &optional no-decode accept-type-regexp)
  "Retrieve content of local URL and insert it to the working buffer.
This function will return content-type of URL as string when retrieval
succeed.  If NO-DECODE, set the multibyte flag of the working buffer
to nil.  Only contents whose content-type matches ACCEPT-TYPE-REGEXP
are retrieved."
  (let ((type (w3m-local-content-type url))
	(file))
    (when (or (not accept-type-regexp)
	      (string-match accept-type-regexp type))
      (setq file (w3m-url-to-file-name url))
      (w3m-with-work-buffer
	(delete-region (point-min) (point-max))
	(if (and (string-match "^text/" type)
		 (not no-decode))
	    (progn
	      (set-buffer-multibyte t)
	      (insert-file-contents file))
	  (set-buffer-multibyte nil)
	  (let ((coding-system-for-read
		 (w3m-static-if (boundp 'MULE) '*noconv* 'binary))
		(file-coding-system-for-read
		 (w3m-static-if (boundp 'MULE) '*noconv* 'binary))
		jka-compr-compression-info-list
		jam-zcat-filename-list
		format-alist)
	    (insert-file-contents file)))))
    type))


;;; Retrieve data via HTTP:
(defun w3m-remove-redundant-spaces (str)
  "Remove spaces/tabs at the front of a string and at the end of a string"
  (save-match-data
    (if (string-match "^[ \t\r\f\n]+" str)
	(setq str (substring str (match-end 0))))
    (if (string-match "[ \t\r\f\n]+$" str)
	(setq str (substring str 0 (match-beginning 0)))))
  str)

(defun w3m-w3m-get-header (url &optional no-cache)
  "Return the header string of the URL.
If optional argument NO-CACHE is non-nil, cache is not used."
  (or (unless no-cache
	(w3m-cache-request-header url))
      (with-temp-buffer
	(let ((w3m-current-url url))
	  (w3m-message "Request sent, waiting for response...")
	  (w3m-exec-process "-dump_head" url)
	  (w3m-message "Request sent, waiting for response... done")
	  (w3m-cache-header url (buffer-string))))))

(defun w3m-w3m-check-header (url &optional no-cache)
  "Ask the header of the URL to HTTP server.
If optional argument NO-CACHE is non-nil, cache is not used."
  (w3m-with-work-buffer
    (delete-region (point-min) (point-max))
    (insert (w3m-w3m-get-header url no-cache))
    (goto-char (point-min))
    (let ((case-fold-search t)
	  length type charset)
      (if (re-search-forward "^content-type:\\([^\r\n]+\\)\r*$" nil t)
	  (progn
	    (setq type (match-string 1))
	    (if (string-match ";[ \t]*charset=" type)
		(setq charset (w3m-remove-redundant-spaces
			       (substring type (match-end 0)))
		      type (w3m-remove-redundant-spaces
			    (substring type 0 (match-beginning 0))))
	      (setq type (w3m-remove-redundant-spaces type)))))
      (goto-char (point-min))
      (when (and (re-search-forward "HTTP/1\\.[0-9] 200" nil t)
		 (re-search-forward "^content-length:\\([^\r\n]+\\)\r*$" nil t))
	(setq length (string-to-number (match-string 1))))
      (list (or type (w3m-local-content-type url) "unknown")
	    charset
	    length))))

(defun w3m-pretty-length (n)
  ;; This function imported from url.el.
  (cond
   ((< n 1024)
    (format "%d bytes" n))
   ((< n (* 1024 1024))
    (format "%dk" (/ n 1024.0)))
   (t
    (format "%2.2fM" (/ n (* 1024 1024.0))))))

(defun w3m-w3m-retrieve (url &optional no-decode accept-type-regexp no-cache)
  "Retrieve content of URL with w3m and insert it to the working buffer.
This function will return content-type of URL as string when retrieval
succeed.  If NO-DECODE, set the multibyte flag of the working buffer
to nil.  Only contents whose content-type matches ACCEPT-TYPE-REGEXP
are retrieved."
  (let ((headers (w3m-w3m-check-header url no-cache)))
    (when headers
      (let ((type    (car headers))
	    (charset (nth 1 headers))
	    (length  (nth 2 headers)))
	(when (or (not accept-type-regexp)
		  (string-match accept-type-regexp type))
	  (w3m-with-work-buffer
	    (delete-region (point-min) (point-max))
	    (set-buffer-multibyte nil)
	    (or
	     (unless no-cache
	       (when (w3m-cache-request-contents url)
		 (and (string-match "^text/" type)
		      (unless no-decode
			(w3m-decode-buffer type charset)))
		 type))
	     (let* ((buflines)
		    (w3m-current-url url)
		    (w3m-w3m-retrieve-length length)
		    (w3m-process-message
		     (lambda ()
		       (if w3m-w3m-retrieve-length
			   (w3m-message
			    "Reading... %s of %s (%d%%)"
			    (w3m-pretty-length (buffer-size))
			    (w3m-pretty-length w3m-w3m-retrieve-length)
			    (/ (* (buffer-size) 100) w3m-w3m-retrieve-length))
			 (w3m-message "Reading... %s"
				      (w3m-pretty-length (buffer-size)))))))
	       (w3m-message "Reading...")
	       (delete-region (point-min) (point-max))
	       (w3m-exec-process "-dump_source" url)
	       (w3m-message "Reading... done")
	       (cond
		((and length (eq w3m-executable-type 'cygwin))
		 (setq buflines (count-lines (point-min) (point-max)))
		 (cond
		  ;; no bugs in output.
		  ((= (buffer-size) length))
		  ;; new-line character is replaced to CRLF.
		  ((or (= (buffer-size) (+ length buflines))
		       (= (buffer-size) (+ length buflines -1)))
		   (while (search-forward "\r\n" nil t)
		     (delete-region (- (point) 2) (1- (point)))))))
		((and length (> (buffer-size) length))
		 (delete-region (point-min) (- (point-max) length)))
		((string= "text/html" type)
		 ;; Remove cookies.
		 (goto-char (point-min))
		 (while (and (not (eobp))
			     (looking-at "Received cookie: "))
		   (forward-line 1))
		 (skip-chars-forward " \t\r\f\n")
		 (if (or (looking-at "<!DOCTYPE")
			 (looking-at "<HTML>")) ; for eGroups.
		     (delete-region (point-min) (point)))))
	       (w3m-cache-contents url (current-buffer))
	       (and (string-match "^text/" type)
		    (not no-decode)
		    (w3m-decode-buffer type charset))
	       type))))))))

(defvar w3m-cid-retrieve-function-alist nil)

(defun w3m-retrieve (url &optional no-decode accept-type-regexp no-cache)
  "Retrieve content of URL and insert it to the working buffer.
This function will return content-type of URL as string when retrieval
succeed.  If NO-DECODE, set the multibyte flag of the working buffer
to nil.  Only contents whose content-type matches ACCEPT-TYPE-REGEXP
are retrieved."
  (cond
   ((string-match "^about:" url)
    (let (func)
      (if (and (string-match "^about://\\([^/]+\\)/" url)
	       (setq func (intern-soft
			   (concat "w3m-about-" (match-string 1 url))))
	       (fboundp func))
	  (funcall func url no-decode accept-type-regexp no-cache)
	(w3m-about url no-decode accept-type-regexp no-cache))))
   ((string-match "^\\(file:\\|/\\)" url)
    (w3m-local-retrieve url no-decode accept-type-regexp))
   ((string-match "^cid:" url)
    (let ((func (cdr (assq major-mode w3m-cid-retrieve-function-alist))))
      (when func
	(funcall func url no-decode accept-type-regexp no-cache))))
   (t
    (w3m-w3m-retrieve url no-decode accept-type-regexp no-cache))))

(defun w3m-download (url &optional filename no-cache)
  (unless filename
    (setq filename (w3m-read-file-name nil nil url)))
  (if (w3m-retrieve url t nil no-cache)
      (with-current-buffer (get-buffer w3m-work-buffer-name)
	(let ((buffer-file-coding-system
	       (w3m-static-if (boundp 'MULE) '*noconv* 'binary))
	      (coding-system-for-write
	       (w3m-static-if (boundp 'MULE) '*noconv* 'binary))
	      jka-compr-compression-info-list
	      jam-zcat-filename-list
	      format-alist)
	  (if (or (not (file-exists-p filename))
		  (y-or-n-p (format "File(%s) is aleready exists. Overwrite? " filename)))
	      (write-region (point-min) (point-max) filename))))
    (error "Unknown URL: %s" url)))

(defun w3m-content-type (url &optional no-cache)
  (cond
   ((string-match "^about:" url) "text/html")
   ((string-match "^\\(file:\\|/\\)" url)
    (w3m-local-content-type url))
   (t (car (w3m-w3m-check-header url no-cache)))))


;;; Retrieve data via FTP:
(defun w3m-exec-ftp (url)
  (let ((ftp (w3m-convert-ftp-to-emacsen url))
	(file (file-name-nondirectory url)))
    (if (string-match "\\(\\.gz\\|\\.bz2\\|\\.zip\\|\\.lzh\\)$" file)
	(copy-file ftp (w3m-read-file-name nil nil file))
      (dired-other-window ftp))))

(defun w3m-convert-ftp-to-emacsen (url)
  (or (and (string-match "^ftp://?\\([^/@]+@\\)?\\([^/]+\\)\\(/~/\\)?" url)
	   (concat "/"
		   (if (match-beginning 1)
		       (substring url (match-beginning 1) (match-end 1))
		     "anonymous@")
		   (substring url (match-beginning 2) (match-end 2))
		   ":"
		   (substring url (match-end 2))))
      (error "URL is strange.")))

(defun w3m-rendering-region (start end)
  "Rendering data in current buffer as HTML."
  (let ((coding-system-for-read w3m-output-coding-system)
	(coding-system-for-write w3m-input-coding-system)
	(default-process-coding-system
	  (cons w3m-output-coding-system w3m-input-coding-system)))
    (w3m-message "Rendering...")
    (if w3m-use-form
	(w3m-form-parse-region start end))
    (apply 'call-process-region
	   start end w3m-command t t nil
	   (mapcar (lambda (x)
		     (if (stringp x)
			 x
		       (prin1-to-string (eval x))))
		   w3m-command-arguments))
    (goto-char (point-min))
    (w3m-message "Rendering... done")
    (let (title)
      (mapcar (lambda (regexp)
		(goto-char 1)
		(when (re-search-forward regexp nil t)
		  (setq title (match-string 1))
		  (delete-region (match-beginning 0) (match-end 0))))
	      '("<title_alt[ \t\n]+title=\"\\([^\"]+\\)\">"
		"<title>\\([^<]\\)</title>"))
      (if (and (null title)
	       (stringp w3m-current-url)
	       (< 0 (length (file-name-nondirectory w3m-current-url))))
	  (setq title (file-name-nondirectory w3m-current-url)))
      (setq w3m-current-title (or title "<no-title>")))))

(defun w3m-exec (url &optional buffer no-cache)
  "Download URL with w3m to the BUFFER.
If BUFFER is nil, all data is placed to the current buffer.  When new
content is retrieved and hald-dumped data is placed in the BUFFER,
this function returns t.  Otherwise, returns nil."
  (save-excursion
    (if buffer (set-buffer buffer))
    (if (and (string-match "^ftp://" url)
	     (not (string= "text/html" (w3m-local-content-type url))))
	(progn (w3m-exec-ftp url) nil)
      (let ((type (w3m-retrieve url nil "^text/" no-cache)))
	(if type
	    (if (string-match "^text/" type)
		(let (buffer-read-only)
		  (setq w3m-current-url url)
		  (setq w3m-url-history (cons url w3m-url-history))
		  (setq-default w3m-url-history
				(cons url (default-value 'w3m-url-history)))
		  (delete-region (point-min) (point-max))
		  (insert-buffer w3m-work-buffer-name)
		  (if (string= "text/html" type)
		      (progn (w3m-rendering-region (point-min) (point-max)) t)
		    (setq w3m-current-title (file-name-nondirectory url))
		    nil))
	      (w3m-message "Requested URL has an unsuitable content type: %s" type)
	      nil)
	  (error "Unknown URL: %s" url))))))


(defun w3m-search-name-anchor (name &optional quiet)
  (interactive "sName: ")
  (let ((pos (point-min)))
    (catch 'found
      (while (setq pos (next-single-property-change pos 'w3m-name-anchor))
	(when (equal name (get-text-property pos 'w3m-name-anchor))
	  (goto-char pos)
	  (throw 'found t))
	(setq pos (next-single-property-change pos 'w3m-name-anchor)))
      (unless quiet
	(message "Not found such name anchor."))
      nil)))


(defun w3m-view-previous-page (&optional arg)
  (interactive "p")
  (unless arg (setq arg 1))
  (let ((url (nth arg w3m-url-history)))
    (when url
      (let (w3m-url-history) (w3m-goto-url url))
      ;; restore last position
      (w3m-arrived-restore-position url)
      (setq w3m-url-history
	    (nthcdr arg w3m-url-history)))))

(defun w3m-view-previous-point ()
  (interactive)
  (w3m-arrived-restore-position w3m-current-url))

(defun w3m-expand-url (url base)
  "Convert URL to absolute, and canonicalize it."
  (save-match-data
    (if (not base) (setq base ""))
    (if (string-match "^[^:/]+://[^/]*$" base)
	(setq base (concat base "/")))
    (cond
     ;; URL is relative on BASE.
     ((string-match "^#" url)
      (concat base url))
     ;; URL has absolute spec.
     ((string-match "^[^:/]+:" url)
      url)
     ((string-match "^/" url)
      (if (string-match "^\\([^:/]+://[^/]*\\)/" base)
	  (concat (match-string 1 base) url)
	url))
     (t
      (let ((server "") path)
	(if (string-match "^\\([^:]+://[^/]*\\)/" base)
	    (setq server (match-string 1 base)
		  base (substring base (match-end 1))))
	(setq path (expand-file-name url (file-name-directory base)))
	;; remove drive (for Win32 platform)
	(if (string-match "^.:" path)
	    (setq path (substring path (match-end 0))))
	(concat server path))))))
 
(defun w3m-view-this-url (&optional arg)
  "*View the URL of the link under point."
  (interactive "P")
  (let ((url (w3m-anchor)) (act (w3m-action)))
    (cond
     (url (w3m-goto-url url arg))
     (act (eval act)))))

(defun w3m-mouse-view-this-url (event)
  (interactive "e")
  (mouse-set-point event)
  (let ((url (w3m-anchor)) (img (w3m-image)))
    (cond
     (url (w3m-view-this-url))
     (img (w3m-view-image))
     (t (message "No URL at point.")))))

(defun w3m-external-view (url)
  (let* ((type (w3m-content-type url))
	 (method (nth 2 (assoc type w3m-content-type-alist))))
    (cond
     ((not method)
      (error "Unknown content type: %s" type))
     ((functionp method)
      (funcall method url))
     ((consp method)
      (let ((command (car method))
	    (arguments (cdr method))
	    (file (make-temp-name
		   (expand-file-name "w3mel" w3m-profile-directory)))
	    (proc))
	(unwind-protect
	    (with-current-buffer
		(generate-new-buffer " *w3m-external-view*")
	      (if (memq 'file arguments) (w3m-download url file))
	      (setq proc
		    (apply 'start-process
			   "w3m-external-view"
			   (current-buffer)
			   command
			   (mapcar (function eval) arguments)))
	      (setq w3m-process-temp-file file)
	      (set-process-sentinel
	       proc
	       (lambda (proc event)
		 (and (string-match "^\\(finished\\|exited\\)" event)
		      (buffer-name (process-buffer proc))
		      (save-excursion
			(set-buffer (process-buffer proc))
			(if (file-exists-p w3m-process-temp-file)
			    (delete-file w3m-process-temp-file)))
		      (kill-buffer (process-buffer proc))))))
	  (if (file-exists-p file)
	      (unless (and (processp proc)
			   (memq (process-status proc) '(run stop)))
		(delete-file file)))))))))

(defun w3m-view-image ()
  "*View the image under point."
  (interactive)
  (let ((url (w3m-image)))
    (if url
	(w3m-external-view url)
      (message "No file at point."))))

(defun w3m-save-image ()
  "*Save the image under point to a file."
  (interactive)
  (let ((url (w3m-image)))
    (if url
	(w3m-download url)
      (message "No file at point."))))

(defun w3m-view-current-url-with-external-browser ()
  "*View this URL."
  (interactive)
  (let ((url (w3m-anchor)))
    (or url
	(and (y-or-n-p (format "Browse <%s> ? " w3m-current-url))
	     (setq url w3m-current-url)))
    (when url
      (message "Browse <%s>" url)
      (w3m-external-view url))))

(defun w3m-download-this-url ()
  "*Download the URL of the link under point to a file."
  (interactive)
  (let ((url (w3m-anchor)))
    (if url
	(progn
	  (w3m-download url)
	  (w3m-refontify-anchor (current-buffer)))
      (message "No URL at point."))))

(defun w3m-print-current-url ()
  "*Print the URL of current page and push it into kill-ring."
  (interactive)
  (kill-new w3m-current-url)
  (message "%s" w3m-current-url))

(defun w3m-print-this-url ()
  "*Print the URL of the link under point."
  (interactive)
  (let ((url (w3m-anchor)))
    (message "%s" (or url "Not found"))))

(defun w3m-save-this-url ()
  (interactive)
  (let ((url (w3m-anchor)))
    (if url (kill-new url))))

(defun w3m-goto-next-anchor ()
  ;; move to the end of the current anchor
  (when (w3m-anchor)
    (goto-char (next-single-property-change (point) 'w3m-href-anchor)))
  ;; find the next anchor
  (or (w3m-anchor)
      (let ((pos (next-single-property-change (point) 'w3m-href-anchor)))
	(if pos (progn (goto-char pos) t) nil))))

(defun w3m-next-anchor (&optional arg)
  "*Move cursor to the next anchor."
  (interactive "p")
  (unless arg (setq arg 1))
  (if (< arg 0)
      (w3m-previous-anchor (- arg))
    (while (> arg 0)
      (unless (w3m-goto-next-anchor)
	;; search from the beginning of the buffer
	(goto-char (point-min))
	(w3m-goto-next-anchor))
      (setq arg (1- arg)))
    (w3m-print-this-url)))

(defun w3m-goto-previous-anchor ()
  ;; move to the beginning of the current anchor
  (when (w3m-anchor)
    (goto-char (previous-single-property-change (1+ (point))
						'w3m-href-anchor)))
  ;; find the previous anchor
  (let ((pos (previous-single-property-change (point) 'w3m-href-anchor)))
    (if pos (goto-char
	     (if (w3m-anchor pos) pos
	       (previous-single-property-change pos 'w3m-href-anchor))))))

(defun w3m-previous-anchor (&optional arg)
  "Move cursor to the previous anchor."
  (interactive "p")
  (unless arg (setq arg 1))
  (if (< arg 0)
      (w3m-next-anchor (- arg))
    (while (> arg 0)
      (unless (w3m-goto-previous-anchor)
	;; search from the end of the buffer
	(goto-char (point-max))
	(w3m-goto-previous-anchor))
      (setq arg (1- arg)))
    (w3m-print-this-url)))


(defun w3m-view-bookmark ()
  (interactive)
  (if (file-readable-p w3m-bookmark-file)
      (w3m (w3m-expand-file-name-as-url w3m-bookmark-file))))


(defun w3m-copy-buffer (buf &optional newname and-pop) "\
Create a twin copy of the current buffer.
if NEWNAME is nil, it defaults to the current buffer's name.
if AND-POP is non-nil, the new buffer is shown with `pop-to-buffer'."
  (interactive (list (current-buffer)
		     (if current-prefix-arg (read-string "Name: "))
		     t))
  (setq newname (or newname (buffer-name)))
  (if (string-match "<[0-9]+>\\'" newname)
      (setq newname (substring newname 0 (match-beginning 0))))
  (with-current-buffer buf
    (let ((ptmin (point-min))
	  (ptmax (point-max))
	  (content (save-restriction (widen) (buffer-string)))
	  (mode major-mode)
	  (lvars (buffer-local-variables))
	  (new (generate-new-buffer (or newname (buffer-name)))))
      (with-current-buffer new
	;;(erase-buffer)
	(insert content)
	(narrow-to-region ptmin ptmax)
	(funcall mode)			;still needed??  -sm
	(mapcar (lambda (v)
		  (if (not (consp v)) (makunbound v)
		    (condition-case ()	;in case var is read-only
			(set (make-local-variable (car v)) (cdr v))
		      (error nil))))
		lvars)
	(when and-pop (pop-to-buffer new))
	new))))


(defvar w3m-mode-map nil)
(unless w3m-mode-map
  (let ((map (make-keymap)))
    (define-key map " " 'scroll-up)
    (define-key map "b" 'scroll-down)
    (define-key map [backspace] 'scroll-down)
    (define-key map [delete] 'scroll-down)
    (define-key map "h" 'backward-char)
    (define-key map "j" 'next-line)
    (define-key map "k" 'previous-line)
    (define-key map "l" 'forward-char)
    (define-key map "J" (lambda () (interactive) (scroll-up 1)))
    (define-key map "K" (lambda () (interactive) (scroll-up -1)))
    (define-key map "G" 'goto-line)
    (define-key map "\C-?" 'scroll-down)
    (define-key map "\t" 'w3m-next-anchor)
    (define-key map [(shift tab)] 'w3m-previous-anchor)
    (define-key map [down] 'w3m-next-anchor)
    (define-key map "\M-\t" 'w3m-previous-anchor)
    (define-key map [up] 'w3m-previous-anchor)
    (define-key map "\C-m" 'w3m-view-this-url)
    (define-key map [right] 'w3m-view-this-url)
    (if (featurep 'xemacs)
	(define-key map [(button2)] 'w3m-mouse-view-this-url)
      (define-key map [mouse-2] 'w3m-mouse-view-this-url))
    (define-key map "\C-c\C-b" 'w3m-view-previous-point)
    (define-key map [left] 'w3m-view-previous-page)
    (define-key map "B" 'w3m-view-previous-page)
    (define-key map "d" 'w3m-download-this-url)
    (define-key map "u" 'w3m-print-this-url)
    (define-key map "I" 'w3m-view-image)
    (define-key map "\M-I" 'w3m-save-image)
    (define-key map "c" 'w3m-print-current-url)
    (define-key map "M" 'w3m-view-current-url-with-external-browser)
    (define-key map "g" 'w3m)
    (define-key map "t" 'w3m-toggle-inline-images)
    (define-key map "U" 'w3m)
    (define-key map "V" 'w3m)
    (define-key map "v" 'w3m-view-bookmark)
    (define-key map "q" 'w3m-quit)
    (define-key map "Q" (lambda () (interactive) (w3m-quit t)))
    (define-key map "\M-n" 'w3m-copy-buffer)
    (define-key map "R" 'w3m-reload-this-page)
    (define-key map "?" 'describe-mode)
    (define-key map "\M-a" 'w3m-bookmark-add-this-url)
    (define-key map "a" 'w3m-bookmark-add-current-url)
    (define-key map ">" 'w3m-scroll-left)
    (define-key map "<" 'w3m-scroll-right)
    (setq w3m-mode-map map)))

(defun w3m-alive-p ()
  "Return t, when w3m is running.  Otherwise return nil."
  (catch 'alive
    (save-current-buffer
      (dolist (buf (buffer-list))
	(set-buffer buf)
	(when (eq major-mode 'w3m-mode)
	  (throw 'alive t))))
    nil))

(defun w3m-quit (&optional force)
  (interactive "P")
  (when (or force
	    (y-or-n-p "Do you want to exit w3m? "))
    (kill-buffer (current-buffer))
    (unless (w3m-alive-p)
      ;; If no w3m is running, then destruct all data.
      (w3m-cache-shutdown)
      (w3m-arrived-shutdown)
      (w3m-kill-all-buffer))))


(defun w3m-mode ()
  "\\<w3m-mode-map>
   Major mode to browsing w3m buffer.

\\[w3m-view-this-url]	View this url.
\\[w3m-mouse-view-this-url]	View this url.
\\[w3m-reload-this-page]	Reload this page.
\\[w3m-next-anchor]	Jump to next anchor.
\\[w3m-previous-anchor]	Jump to previous anchor.
\\[w3m-view-previous-page]	Back to previous page.

\\[w3m-download-this-url]	Download this url.
\\[w3m-print-this-url]	Print this url.
\\[w3m-view-image]	View image.
\\[w3m-save-image]	Save image.

\\[w3m-print-current-url]	Print current url.
\\[w3m-view-current-url-with-external-browser]	View current url with external browser.

\\[scroll-up]	Scroll up.
\\[scroll-down]	Scroll down.
\\[w3m-scroll-left]	Scroll to left.
\\[w3m-scroll-right]	Scroll to right.

\\[next-line]	Next line.
\\[previous-line]	Previous line.

\\[forward-char]	Forward char.
\\[backward-char]	Backward char.

\\[goto-line]	Jump to line.
\\[w3m-view-previous-point]	w3m-view-previous-point.

\\[w3m]	w3m.
\\[w3m-view-bookmark]	w3m-view-bookmark.
\\[w3m-copy-buffer]	w3m-copy-buffer.

\\[w3m-quit]	w3m-quit.
\\[describe-mode]	describe-mode.
"
  (kill-all-local-variables)
  (buffer-disable-undo)
  (setq major-mode 'w3m-mode)
  (setq mode-name "w3m")
  (use-local-map w3m-mode-map)
  (setq truncate-lines t)
  (run-hooks 'w3m-mode-hook))

(defun w3m-scroll-left (arg)
  "Scroll to left.
Scroll size is `w3m-horizontal-scroll-size' columns
or prefix ARG columns."
  (interactive "P")
  (scroll-left (if arg
		   (prefix-numeric-value arg)
		 w3m-horizontal-scroll-columns)))

(defun w3m-scroll-right (arg)
  "Scroll to right.
Scroll size is `w3m-horizontal-scroll-size' columns
or prefix ARG columns."
  (interactive "P")
  (scroll-right (if arg
		    (prefix-numeric-value arg)
		  w3m-horizontal-scroll-columns)))

(defun w3m-mailto-url (url)
  (if (and (symbolp w3m-mailto-url-function)
	   (fboundp w3m-mailto-url-function))
      (funcall w3m-mailto-url-function url)
    (let (comp)
      ;; Require `mail-user-agent' setting
      (if (not (and (boundp 'mail-user-agent)
		    mail-user-agent
		    (setq comp (intern-soft (concat (symbol-name mail-user-agent)
						    "-compose")))
		    (fboundp comp)))
	  (error "You must specify valid `mail-user-agent'."))
      ;; Use rfc2368.el if exist.
      ;; rfc2368.el is written by Sen Nagata.
      ;; You can find it in "contrib" directory of Mew package
      ;; or in "utils" directory of Wanderlust package.
      (if (or (featurep 'rfc2368)
	      (condition-case nil (require 'rfc2368) (error nil)))
	  (let ((info (rfc2368-parse-mailto-url url)))
	    (apply comp (mapcar (lambda (x)
				  (cdr (assoc x info)))
				'("To" "Subject"))))
	;; without rfc2368.el.
	(funcall comp (match-string 1 url))))))


(defun w3m-goto-url (url &optional reload)
  "Retrieve URL and display it in this buffer."
  (let (name)
    (cond
     ;; process mailto: protocol
     ((string-match "^mailto:\\(.*\\)" url)
      (w3m-mailto-url url))
     (t
      (w3m-arrived-setup)
      (w3m-arrived-store-position w3m-current-url)
      (w3m-arrived-add url)
      (when (string-match "#\\([^#]+\\)$" url)
	(setq name (match-string 1 url)
	      url (substring url 0 (match-beginning 0)))
	(w3m-arrived-add url))
      (if (not (w3m-exec url nil reload))
	  (w3m-refontify-anchor)
	(w3m-fontify)
	(setq w3m-display-inline-image-status 'off)
	(if w3m-display-inline-image
	    (w3m-toggle-inline-images 'force reload))
	(setq buffer-read-only t)
	(set-buffer-modified-p nil)
	(or (and name (w3m-search-name-anchor name))
	    (goto-char (point-min))))))))


(defun w3m-reload-this-page (&optional arg)
  "Reload current page without cache."
  (interactive "P")
  (let ((w3m-display-inline-image (if arg t w3m-display-inline-image)))
    (setq w3m-url-history (cdr w3m-url-history))
    (w3m-goto-url w3m-current-url 'reload)))


(defun w3m (url &optional args)
  "Interface for w3m on Emacs."
  (interactive (list (w3m-input-url)))
  (set-buffer (get-buffer-create "*w3m*"))
  (or (eq major-mode 'w3m-mode)
      (w3m-mode))
  (setq mode-line-buffer-identification
	(list "%b" " / " 'w3m-current-title))
  (w3m-goto-url url)
  (switch-to-buffer (current-buffer))
  (run-hooks 'w3m-hook))


(defun w3m-browse-url (url &optional new-window)
  "w3m interface function for browse-url.el."
  (interactive
   (progn
     (require 'browse-url)
     (browse-url-interactive-arg "w3m URL: ")))
  (if new-window (split-window))
  (w3m url))

(defun w3m-find-file (file)
  "w3m Interface function for local file."
  (interactive "fFilename: ")
  (w3m (w3m-expand-file-name-as-url file)))

;; bookmark operations

(defun w3m-bookmark-file-modified-p ()
  "Predicate for FILE is something modified."
  (and (file-exists-p w3m-bookmark-file)
       w3m-bookmark-file-time-stamp
       (not (equal (elt (file-attributes w3m-bookmark-file) 5)
		   w3m-bookmark-file-time-stamp))))

;; bookmark data format
;; bookmark has some section.
;; section has some entries.
;; entry is pair of link name (title) and url
;; for example:
;; bookmark := ( ("My Favorites"                    ; section
;;                ( "title1" . "http://foo.com/" )  ; entry
;;                ( "title2" . "http://bar.org/" )) ; entry
;;               ("For Study"                       ; section
;;                ( "Title3" . "http://baz.net/" )) ; entry
;;
;; In w3m, section is h2 level contents. (HTML/BODY/H2)
;; entry is A item (represented as UL/LI)
;; `w3m-bookmark-parse' assumes above
;;  because this is easy implementation. :-)

(defun w3m-bookmark-parse ()
  "Parse current buffer and returns bookmark data alist for internal."
  (let (bookmark tag url str)
    (goto-char 1)
    (while (re-search-forward
	    "<\\(h2\\|a\\)\\( *href=\"\\([^\"]+\\)\"[^>]*\\)?>" nil t)
      (setq tag (match-string 1))
      (cond
       ((string= tag "h2")
	;; make new section (in top)
	(setq bookmark (cons (list (buffer-substring
				    (match-end 0)
				    (progn (re-search-forward "</h2>")
					   (match-beginning 0))))
			     bookmark)))
       ((string= tag "a")
	(if (null (match-beginning 2))
	    (error "parse error, href attribute is expected."))
	(setq url (match-string 3)
	      str (buffer-substring (match-end 0)
				    (progn
				      (re-search-forward "</a>")
				      (match-beginning 0))))
	(setcar bookmark (cons (cons str url) (car bookmark))))
       (t (error "parse error, unknown tag is matched."))))
    ;; reverse entries and sections
    (nreverse (mapcar 'nreverse bookmark))))



(defun w3m-bookmark-load (&optional file)
  "Load bookmark from FILE.
Parsed bookmark data is hold in `w3m-bookmark-data'."
  (or file
      (setq file w3m-bookmark-file))	; default name
  (message "Loading bookmarks...")
  (with-temp-buffer
    (if (file-exists-p w3m-bookmark-file)
	(insert-file-contents w3m-bookmark-file))
    ;; parse
    (setq w3m-bookmark-data (w3m-bookmark-parse)
	  w3m-bookmark-file-time-stamp (elt (file-attributes file) 5)))
  (message "Loading bookmarks...done"))


(defun w3m-bookmark-save (&optional file)
  "Save internal bookmark data into bookmark file as w3m format."
  (or file
      (setq file w3m-bookmark-file))	; default name
  ;; check output directory
  (if (not (file-writable-p file))
      (message "Can't write! Bookmark file is not saved.")
    ;;
    (with-temp-buffer
      ;; print beginning of html
      (insert "<html><head><title>Bookmarks</title></head>\n"
	      "<body>\n"
	      "<h1>Bookmarks</h1>\n")
      (dolist (entries w3m-bookmark-data)
	(insert "<h2>" (car entries) "</h2>\n"
		"<ul>\n")
	(dolist (ent (cdr entries))
	  (insert "<li><a href=\"" (cdr ent) "\">" (car ent) "</a>\n"))
	(insert "<!--End of section (do not delete this comment)-->\n"
		"</ul>\n"))
      ;; print end of html
      (insert "</body>\n"
	      "</html>\n")
      ;; write to file!
      (let ((coding-system-for-write w3m-bookmark-file-coding-system))
	(write-region (point-min) (point-max) file))
      (setq w3m-bookmark-file-time-stamp (elt (file-attributes file) 5))
      (message "Saved to '%s'" file))))

(defun w3m-bookmark-data-prepare ()
  "Prepare for bookmark operation.
If bookmark data is not loaded, load it.
If bookmark file is modified since last load, ask reloading."
  (if (and (null w3m-bookmark-file-time-stamp)
	   (null w3m-bookmark-data)
	   (file-exists-p w3m-bookmark-file))
      (w3m-bookmark-load w3m-bookmark-file)))


(defun w3m-bookmark-add (url &optional title section)
  "Add URL to bookmark data and save it to file.
Optional argument TITLE is title of link.
SECTION is category name in bookmark."
  (let (sec ent)
    (w3m-bookmark-data-prepare)
    ;; check time stamp of bookmark file (localy modified?)
    (if (and (w3m-bookmark-file-modified-p)
	     (y-or-n-p "Bookmark file is modified. Reload it? (y/n): "))
	(w3m-bookmark-load))
    ;; go on ...
    ;; ask section (with completion).
    (setq sec (completing-read
	       "Section: "
	       w3m-bookmark-data nil nil nil
	       'w3m-bookmark-section-history ))
    (if (string-match sec "^ *$")
	(error "You must specify section name."))
    ;; ask title (with default)
    (setq title (read-string "Title: " title 'w3m-bookmark-title-history))
    (if (string-match sec "^ *$")
	(error "You must specify title."))
    ;; add it to internal bookmark data.
    (if (setq ent (assoc sec w3m-bookmark-data))
	;; add to existing section
	(nconc ent (list (cons title url))) ; add to tail
      ;; add as new section
      (setq w3m-bookmark-data
	    (nconc w3m-bookmark-data
		   (list (list sec (cons title url))))))
    ;; then save to file. (xxx, force saving, should we ask?)
    (w3m-bookmark-save)))


(defun w3m-bookmark-add-this-url ()
  "Add link under cursor to bookmark."
  (interactive)
  (if (null (w3m-anchor))
      (message "No anchor.")		; nothing to do
    (let ((url (w3m-anchor))
	  (title (buffer-substring-no-properties
		  (previous-single-property-change (1+ (point))
						   'w3m-href-anchor)
		  (next-single-property-change (point) 'w3m-href-anchor))))
      (w3m-bookmark-add url title))
    (message "Added.")))


(defun w3m-bookmark-add-current-url (&optional arg)
  "Add link of current page to bookmark.
With prefix, ask new url to add instead of current page."
  (interactive "P")
  (w3m-bookmark-add (if (null arg) w3m-current-url (w3m-input-url))
		    w3m-current-title)
  (message "Added."))


(defun w3m-cygwin-path (path)
  "Convert win32 path into cygwin format.
ex.) c:/dir/file => //c/dir/file"
  (if (string-match "^\\([A-Za-z]\\):" path)
      (replace-match "//\\1" nil nil path)
    path))


(defun w3m-region (start end)
  "Render region in current buffer and replace with result."
  (interactive "r")
  (save-restriction
    (narrow-to-region start end)
    (w3m-rendering-region start end)
    (w3m-fontify)
    (setq w3m-display-inline-image-status 'off)
    (if w3m-display-inline-image
	(w3m-toggle-inline-images 'force))))


(defun w3m-escape-query-string (str &optional coding)
  (mapconcat
   (lambda (s)
     (w3m-url-encode-string s coding))
   (split-string str)
   "+"))

(defun w3m-search (search-engine query)
  "Search QUERY using SEARCH-ENGINE.
When called interactively with prefix argument, you can choose search
engine deinfed in `w3m-search-engine-alist'.  Otherwise use
`w3m-default-search-engine'."
  (interactive
   (let ((engine
	  (if current-prefix-arg
	      (completing-read
	       (format "Which Engine? (%s): " w3m-default-search-engine)
	       w3m-search-engine-alist nil t)
	    w3m-default-search-engine)))
     (list engine
	   (read-string (format "%s search: " engine)))))
  (unless (string= query "")
    (let ((info (assoc search-engine w3m-search-engine-alist)))
      (if info
	  (w3m (format (cadr info)
		       (w3m-escape-query-string query (caddr info))))
	(error "Unknown search engine: %s" search-engine)))))


;;; About:
(defun w3m-about (url &rest args)
  (w3m-with-work-buffer
    (delete-region (point-min) (point-max)))
  "text/html")


;;; Weather:
(defun w3m-weather (area)
  "*Display weather report."
  (interactive
   (list (if current-prefix-arg
	     (completing-read "Input area: " w3m-weather-url-alist nil t)
	   w3m-weather-default-area)))
  (w3m (format "about://weather/%s" area)))

(defun w3m-about-weather (url &rest args)
  (let (area furl)
    (if (and (string-match "^about://weather/" url)
	     (setq area (substring url (match-end 0))
		   furl (cdr (assoc area w3m-weather-url-alist))))
	(save-excursion
	  (w3m-retrieve furl)
	  (set-buffer w3m-work-buffer-name)
	  (run-hook-with-args 'w3m-weather-filter-functions area)
	  "text/html")
      (w3m-message "Unknown URL: %s" url)
      nil)))

(defun w3m-weather-remove-headers (&rest args)
  "Remove header of the weather forecast page."
  (goto-char (point-min))
  (when (search-forward "<!-- area_s_title -->" nil t)
    (delete-region (point-min) (point))
    (when (search-forward "<img src=\"/common/clear.gif\"")
      (let ((start))
	(and (search-backward "<tr>" nil t)
	     (setq start (point))
	     (search-forward "</tr>" nil t)
	     (delete-region start (point)))))))

(defun w3m-weather-remove-footers (&rest args)
  "Remove footer of the weather forecast page."
  (goto-char (point-max))
  (when (search-backward "<!-- /area_7days -->" nil t)
    (delete-region (point) (point-max))
    (forward-line -2)
    (when (looking-at "<div")
      (delete-region (point) (point-max)))))

(defun w3m-weather-remove-weather-images (&rest args)
  "Remove images which stand for weather forecasts."
  (let ((case-fold-search t) start end)
    (goto-char (point-min))
    (and (re-search-forward
	  "\\(<td[^>]*>天気</td>\\)[ \t\r\f\n]*<td[^>]*><img src=\"/weather/images/"
	  nil t)
	 (setq start (match-beginning 1)
	       end (match-end 1))
	 (search-forward
	  "<tr bgcolor=\"#FFFFFF\">"
	  (prog2 (forward-line 5) (point) (goto-char (match-end 0)))
	  t)
	 (progn
	   (delete-region end (point))
	   (goto-char start)
	   (when (re-search-forward "\\([ \t\r\f\n]rowspan=\"[0-9]+\"\\)[> \t\r\f\n]" end t)
	     (delete-region (match-beginning 1) (match-end 1)))))))

(defun w3m-weather-remove-washing-images (&rest args)
  "Remove images which stand for washing index."
  (let ((case-fold-search t))
    (goto-char (point-min))
    (while (re-search-forward
	    "<td[^>]*>\\(<img src=\"/weather/images/wash[-0-9]*.gif\"[^>]*><br>\\)"
	    nil t)
      (delete-region (match-beginning 1) (match-end 1)))))

(defun w3m-weather-remove-futon-images (&rest args)
  "Remove images which stand for futon index."
  (let ((case-fold-search t))
    (goto-char (point-min))
    (while (re-search-forward
	    "<td[^>]*>\\(<img src=\"/weather/images/bed[-0-9]*.gif\"[^>]*><br>\\)"
	    nil t)
      (delete-region (match-beginning 1) (match-end 1)))))

(defun w3m-weather-remove-week-weather-images (&rest args)
  "Remove images which stand for the weather forecast for the week."
  (let ((case-fold-search t))
    (goto-char (point-min))
    (while (re-search-forward
	    "<td[^>]*>\\(<img src=\"/weather/images/tk[0-9]*.gif\"[^>]*><br>\\)"
	    nil t)
      (delete-region (match-beginning 1) (match-end 1)))))

(defun w3m-weather-insert-title (area &rest args)
  "Insert title."
  (goto-char (point-min))
  (insert "<head><title>Weather forecast of " area "</title></head><body>")
  (goto-char (point-max))
  (insert "</body>"))


(provide 'w3m)
;;; w3m.el ends here.
