;;;
;;; wiliki/format.scm - wiliki markup -> SXML converter
;;;
;;;  Copyright (c) 2003-2005 Shiro Kawai, All rights reserved.
;;;
;;;  Permission is hereby granted, free of charge, to any person
;;;  obtaining a copy of this software and associated documentation
;;;  files (the "Software"), to deal in the Software without restriction,
;;;  including without limitation the rights to use, copy, modify,
;;;  merge, publish, distribute, sublicense, and/or sell copies of
;;;  the Software, and to permit persons to whom the Software is
;;;  furnished to do so, subject to the following conditions:
;;;
;;;  The above copyright notice and this permission notice shall be
;;;  included in all copies or substantial portions of the Software.
;;;
;;;  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;;  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
;;;  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;;  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
;;;  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
;;;  AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
;;;  OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
;;;  IN THE SOFTWARE.
;;;
;;; $Id: format.scm,v 1.40 2005-08-21 10:40:15 shirok Exp $

(define-module wiliki.format
  (use srfi-1)
  (use srfi-2)
  (use srfi-11)
  (use srfi-13)
  (use text.html-lite)
  (use text.tree)
  (use text.tr)
  (use rfc.uri)
  (use util.list)
  (use util.queue)
  (use util.match)
  (use gauche.parameter)
  (use gauche.charconv)
  (use gauche.sequence)
  (use wiliki.parse)
  (use sxml.tools)
  (export <wiliki-formatter>
          <wiliki-page>
          wiliki:persistent-page?
          wiliki:transient-page?
          wiliki:format-wikiname
          wiliki:format-macro
          wiliki:format-time
          wiliki:format-content
          wiliki:formatter
          wiliki:page-stack
          wiliki:page-circular?
          wiliki:current-page
          wiliki:format-page-header
          wiliki:format-page-content
          wiliki:format-page-footer
          wiliki:format-page-body
          wiliki:format-head-elements
          wiliki:format-page
          wiliki:format-line-plainly
          wiliki:calculate-heading-id
          wiliki:sxml->stree
          wiliki:format-diff-pre
          wiliki:format-diff-line
          )
  )
(select-module wiliki.format)

;; This module implements a generic function that translates WiLiki
;; notation to SXML.   It is designed not to depend other parts of
;; WiLiKi so that it can be used for other applications that needs
;; wiki-like formatting capability.

;; A formatter base class.
;; The user can define her own formatter by subclassing this and
;; overloading some methods.

(define-class <wiliki-formatter> ()
  (;; The following slots are only for compatibility to the code
   ;; written with WiLiKi-0.5_pre2.
   ;; They won't be supported officially in future versions; use
   ;; subclassing & methods instead.
   (bracket       :init-keyword :bracket
                  :init-value (lambda (name) (list #`"[[,|name|]]")))
   (macro         :init-keyword :macro
                  :init-value (lambda (expr context)
                                `("##" ,(write-to-string expr))))
   (time          :init-keyword :time
                  :init-value (lambda (time) (x->string time)))
   (body          :init-keyword :body
                  :init-value (lambda (page opts) (fmt-body page opts)))
   (header        :init-keyword :header
                  :init-value (lambda (page opts) '()))
   (footer        :init-keyword :footer
                  :init-value (lambda (page opts) '()))
   (content       :init-keyword :content
                  :init-value (lambda (page opts) (fmt-content page)))
   (head-elements :init-keyword :head-elements
                  :init-value (lambda (page opts) '()))
   ))

;; Global context and the default formatter
(define the-formatter
  (make-parameter (make <wiliki-formatter>)))

(define fmt-context
  (make-parameter '()))

;; These are for convenience of internal use.
(define (fmt-wikiname name)
  (wiliki:format-wikiname (the-formatter) name))

(define (fmt-macro expr context)
  (wiliki:format-macro (the-formatter) expr context))

(define (fmt-time time)
  (wiliki:format-time (the-formatter) time))

;; Utilities



;; similar to sxml:sxml->xml, but deals with stree node, which
;; embeds a string tree.

(define (wiliki:sxml->stree sxml)
  (define (sxml-node type body)
    (define (attr lis r)
      (cond ((null? lis) (reverse! r))
            ((not (= (length+ (car lis)) 2))
             (error "bad attribute in node: " (cons type body)))
            (else
             (attr (cdr lis)
                   (cons `(" " ,(html-escape-string (x->string (caar lis)))
                           "=\"" ,(html-escape-string (x->string (cadar lis)))
                           "\"")
                         r)))))
    (define (rest type lis)
      (if (and (null? lis)
               (memq type '(br area link img param hr input col base meta)))
        '(" />")
        (list* ">" (reverse! (fold node '() lis)) "</" type "\n>")))

    (if (and (pair? body)
             (pair? (car body))
             (eq? (caar body) '@))
      (list* "<" type (attr (cdar body) '()) (rest type (cdr body)))
      (list* "<" type (rest type body)))
    )

  (define (node n r)
    (cond
     ((string? n) (cons (html-escape-string n) r))
     ((and (pair? n) (symbol? (car n)))
      (if (eq? (car n) 'stree)
        (cons (cdr n) r)
        (cons (sxml-node (car n) (cdr n)) r)))
     (else
      ;; badly formed node.  we show it for debugging ease.
      (cons (list "<span class=\"wiliki-alert\">" 
                  (html-escape-string (format "~,,,,50:s" n))
                  "</span\n>")
            r))))

  (node sxml '()))

;;=================================================
;; Formatting: Wiki -> SXML
;;

;; Utility to generate a (mostly) unique id for the headings.
;; Passes a list of heading string stack.
(define (wiliki:calculate-heading-id headings)
  (string-append "H-" (number->string (hash headings) 36)))

;; utility : strips wiki markup and returns a plaintext line.
(define (wiliki:format-line-plainly line)
  (reverse! ((rec (tree-fold tree seed)
               (match tree
                 ("\n" seed)  ;; skip newline
                 ((? string?) (cons tree seed))
                 (('@ . _)  seed)  ;; skip attr node
                 (('@@ . _) seed)  ;; skip aux node
                 (('wiki-name name) (cons name seed))
                 (('wiki-macro . _) seed)
                 ((name . nodes) 
                  (fold tree-fold seed nodes))
                 (else seed)))
             `(x ,@(wiliki-parse-string line))
             '())))
  
;; Page ======================================================

(define page-stack
  (make-parameter '()))

(define (current-page)
  (let1 hist (page-stack)
    (if (null? hist) #f (car hist))))

;; Class <wiliki-page> ---------------------------------------------
;;   Represents a page.
;;
;;   persistent page: a page that is (or will be) stored in DB.
;;         - has 'key' value.
;;         - if mtime is #f, it is a freshly created page before saved.
;;   transient page: other pages created procedurally just for display.
;;         - 'key' slot has #f.

(define-class <wiliki-page> ()
  (;; title - Page title.  For persistent pages, this is set to
   ;;         the same value as the database key.
   (title   :init-value #f :init-keyword :title)
   ;; key   - Database key.  For transient pages, this is #f.
   (key     :init-value #f :init-keyword :key)
   ;; command - A URL parameters to reproduce this page.  Only meaningful
   ;;           for transient pages.
   (command :init-value #f :init-keyword :command)
   ;; extra-head-eleemnts - List of SXML to be inserted in the head element
   ;;           of output html.
   ;;           Useful to add meta info in the auto-generated pages.
   (extra-head-elements :init-value '() :init-keyword :extra-head-elements)
   ;; content - Either a wiliki-marked-up string or SXML.
   (content :init-value "" :init-keyword :content)
   ;; creation and modification times, and users (users not used now).
   (ctime   :init-value (sys-time) :init-keyword :ctime)
   (cuser   :init-value #f :init-keyword :cuser)
   (mtime   :init-value #f :init-keyword :mtime)
   (muser   :init-value #f :init-keyword :muser)
   ))

(define (fmt-content page)
  (define (do-fmt content)
    (expand-page (wiliki-parse-string content)))
  (cond ((string? page) (do-fmt page))
        ((is-a? page <wiliki-page>)
         (if (wiliki:page-circular? page)
           ;; loop in $$include chain detected
           `(p ">>>$$include loop detected<<<")
           (parameterize
               ((page-stack (cons page (page-stack))))
             (if (string? (ref page 'content))
               (do-fmt (ref page 'content))
               (ref page 'content)))))
        (else page)))

;; [SXML] -> [SXML], expanding wiki-name and wiki-macro nodes.
;; 
(define (expand-page sxmls)
  (let rec ((sxmls sxmls)
            (hctx '()))                 ;;headings context
    (match sxmls
      (()  '())
      ((('wiki-name name) . rest)
       (append (wiliki:format-wikiname (the-formatter) name)
               (rec rest hctx)))
      ((('wiki-macro name . args) . rest)
       ;; for the time being...
       (append #`"##(,name ,args)" (rec rest hctx)))
      (((and ((or 'h2 'h3 'h4 'h5 'h6) . _) sxml) . rest)
       ;; extract heading hierarchy to calculate heading id
       (let* ((hn   (sxml:name sxml))
              (hkey (assq 'hkey (sxml:aux-list-u sxml)))
              (hctx2 (extend-headings-context hctx hn hkey)))
         (cons `(,hn ,@(if hkey
                         `((@ (id ,(heading-id hctx2))))
                         '())
                     ,@(rec (sxml:content sxml) hctx))
               (rec rest hctx2))))
      (((and (name . _) sxml) . rest);; generic node
       (cons `(,name ,@(cond ((sxml:attr-list-node sxml) => list)
                             (else '()))
                     ,@(rec (sxml:content sxml) hctx))
             (rec rest hctx)))
      ((other . rest)
       (cons other (rec rest hctx))))))

(define (hn->level hn)
  (find-index (cut eq? hn <>) '(h2 h3 h4 h5 h6)))

(define (extend-headings-context hctx hn hkey)
  (if (not hkey)
    hctx
    (let* ((level (hn->level hn))
           (up (drop-while (lambda (x) (>= (hn->level (car x)) level)) hctx)))
      (acons hn (cadr hkey) up))))

(define (heading-id hctx)
  (wiliki:calculate-heading-id (map cdr hctx)))

(define (wiliki:page-circular? page)
  (member page (page-stack)
          (lambda (p1 p2)
            (and (ref p1 'key) (ref p2 'key)
                 (string=? (ref p1 'key) (ref p2 'key))))))

;; default page body formatter
(define (fmt-body page opts)
  `(,@(wiliki:format-page-header  page opts)
    ,@(wiliki:format-page-content page opts)
    ,@(wiliki:format-page-footer  page opts)))

;;;
;;; Exported functions
;;;

(define wiliki:formatter        the-formatter)
(define wiliki:page-stack       page-stack)
(define wiliki:current-page     current-page)

(define wiliki:format-content   fmt-content)

;; Default formatting methods.
;; Methods are supposed to return SXML nodeset.
;; NB: It is _temporary_ that these methods calling the slot value
;; of the formatter, just to keep the backward compatibility to 0.5_pre2.
;; Do not count on this implementation.  The next release will remove
;; all the closure slots of <wiliki-formatter> and the default behavior
;; will directly be embedded in these methods.

(define-method wiliki:format-wikiname ((fmt <wiliki-formatter>) name)
  ((ref fmt 'bracket) name))
(define-method wiliki:format-wikiname ((name <string>))
  (wiliki:format-wikiname (the-formatter) name))

(define-method wiliki:format-macro ((fmt <wiliki-formatter>) expr context)
  ((ref fmt 'macro) expr context))
(define-method wiliki:format-macro (expr context)
  (wiliki:format-macro (the-formatter) expr context))

(define-method wiliki:format-time ((fmt <wiliki-formatter>) time)
  ((ref fmt 'time) time))
(define-method wiliki:format-time (time)
  (wiliki:format-time (the-formatter) time))

(define-method wiliki:format-page-content ((fmt  <wiliki-formatter>)
                                           page  ;; may be a string
                                           . options)
  ((ref fmt 'content) page options))
(define-method wiliki:format-page-content (page . opts)
  (apply wiliki:format-page-content (the-formatter) page opts))

(define-method wiliki:format-page-body ((fmt  <wiliki-formatter>)
                                        (page <wiliki-page>)
                                        . opts)
  `(,@(apply wiliki:format-page-header  page opts)
    ,@(apply wiliki:format-page-content page opts)
    ,@(apply wiliki:format-page-footer  page opts)))
(define-method wiliki:format-page-body ((page <wiliki-page>) . opts)
  (apply wiliki:format-page-body (the-formatter) page opts))

(define-method wiliki:format-page-header ((fmt  <wiliki-formatter>)
                                          (page <wiliki-page>)
                                          . options)
  ((ref fmt 'header) page options))
(define-method wiliki:format-page-header ((page <wiliki-page>) . opts)
  (apply wiliki:format-page-header (the-formatter) page opts))
  
(define-method wiliki:format-page-footer ((fmt  <wiliki-formatter>)
                                          (page <wiliki-page>)
                                          . options)
  ((ref fmt 'footer) page options))
(define-method wiliki:format-page-footer ((page <wiliki-page>) . opts)
  (apply wiliki:format-page-footer (the-formatter) page opts))

(define-method wiliki:format-head-elements ((fmt  <wiliki-formatter>)
                                            (page <wiliki-page>)
                                            . options)
  (append
   ((ref fmt 'head-elements) page options)
   (ref page 'extra-head-elements)))
(define-method wiliki:format-head-elements ((page <wiliki-page>) . opts)
  (apply wiliki:format-head-elements (the-formatter) page opts))

(define-method wiliki:format-page ((fmt  <wiliki-formatter>)
                                   (page <wiliki-page>)
                                   . opts)
  `(html
    (head ,@(apply wiliki:format-head-elements fmt page opts))
    (body ,@(apply wiliki:format-page-body fmt page opts))))
(define-method wiliki:format-page ((page <wiliki-page>) . opts)
  (apply wiliki:format-page (the-formatter) page opts))

(define (wiliki:persistent-page? page)
  (not (wiliki:transient-page? page)))
(define (wiliki:transient-page? page)
  (not (ref page 'key)))

;; NB: these should also be a generics.
(define (wiliki:format-diff-pre difflines)
  `(pre (@ (class "diff")
           (style "background-color:#ffffff; color:#000000; margin:0"))
        ,@(map wiliki:format-diff-line difflines)))

(define (wiliki:format-diff-line line)
  (define (aline . c)
    `(span (@ (class "diff_added")
              (style "background-color:#ffffff; color: #4444ff"))
           ,@c))
  (define (dline . c)
    `(span (@ (class "diff_deleted")
              (style "background-color:#ffffff; color: #ff4444"))
           ,@c))
  (cond ((string? line) `(span "  " ,line "\n"))
        ((eq? (car line) '+) (aline "+ " (cdr line) "\n"))
        ((eq? (car line) '-) (dline "- " (cdr line) "\n"))
        (else "???")))

(provide "wiliki/format")
