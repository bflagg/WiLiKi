;;
;; Macros used in SchemeCrossReference site
;; included for the reference
;;

(select-module wiliki.macro)
(use srfi-1)
(use srfi-13)
(use util.list)

;;---------------------------------------------------------------
;; SRFI-related macros

(define-reader-macro (srfis . numbers)
  `((p "Implementing " ,@(wiliki:format-wikiname "SRFI") "s: "
       ,@(append-map (lambda (num)
                       (cons " " (wiliki:format-wikiname #"SRFI-~num")))
                     numbers))))

(define (pick-srfis-macro page-record)
  (cond ((#/\[\[$$srfis ([\s\d]+)\]\]/ page-record)
         => (lambda (m)
              (map x->integer (string-tokenize (m 1)))))
        (else #f)))

(define-reader-macro (srfi-implementors-map)
  (let1 tab (make-hash-table 'eqv?)
    (wiliki:db-for-each
     (lambda (pagename record)
       (cond ((pick-srfis-macro record)
              => (cut map (cut hash-table-push! tab <> pagename) <>)))))
    (list
     `(table
       (@ (style "border-width: 0"))
       ,@(map (lambda (srfi-num&title)
                (let* ((num (car srfi-num&title))
                       (title (cdr srfi-num&title))
                       (popularity (length (hash-table-get tab num '())))
                       (bgcolor (case popularity
                                  ((0) "#ffffff")
                                  ((1) "#fff8f8")
                                  ((2) "#fff0f0")
                                  ((3 4) "#ffe0e0")
                                  ((5 6) "#ffcccc")
                                  ((7 8) "#ffaaaa")
                                  (else "#ff8888"))))
                  `(tr
                    (td (@ (style ,#"background-color: ~bgcolor"))
                        ,@(wiliki:format-wikiname #"SRFI-~num")
                        ": ")
                    (td (@ (style ,#"background-color: ~bgcolor"))
                        ,title)
                    (td (@ (style ,#"background-color: ~bgcolor ; font-size: 60%"))
                        ,(format "[~a implementation~a]"
                                 popularity
                                 (if (= popularity 1) "" "s"))))))
              *final-srfis*)))))

(define-reader-macro (srfi-implementors . maybe-num)
  (let* ((num   (x->integer
                 (get-optional maybe-num
                               (or (and-let* ((p (wiliki-current-page))
                                              (t (ref p 'title))
                                              (m (#/SRFI-(\d+)/ t)))
                                     (m 1))
                                   "-1"))))
         (impls (sort (wiliki:db-fold
                       (lambda (pagename record seed)
                         (cond ((pick-srfis-macro record)
                                => (lambda (srfis)
                                     (if (memv num srfis)
                                       (cons pagename seed)
                                       seed)))
                               (else seed)))
                       '()))))
    `((p "SRFI-" ,(x->string num) " is implemented in "
         ,@(if (null? impls)
             '("(none)")
             (append-map (lambda (impl)
                           (cons " " (wiliki:format-wikiname impl)))
                         impls))))))

;;; The SRFI table below can be obtained by the following code snippet.
#|
(use rfc.http)
(define (get-srfi-info kind) ; kind := final | withdrawn | draft
  (receive (s h c) (http-get "srfi.schemers.org" #"/?statuses=~|kind|")
    (unless (string=? s "200")
      (errorf "couldn't retrieve ~a srfi data (~a)" kind s))
    (with-input-from-string c
      (^[]
        (port-fold (^[line seed]
                     (if-let1 m (#/<li class=\"card (\w+)\"/ line)
                       (if (equal? (m 1) (x->string kind))
                         (if-let1 m (#/<a href=\"srfi-\d+\/\"><span[^>]*>(\d+)<\/span><\/a>: <span[^>]*>(.*?)<\/span>/ line)
                           (acons (x->integer (m 1))
                                  (regexp-replace-all #/<\/?\w+>/ (m 2)
                                                      "")
                                  seed)
                           seed)
                         seed)
                       seed))
                   '()
                   read-line)))))
|#

(define *final-srfis*
  '((0 . "Feature-based conditional expansion construct")
    (1 . "List Library")
    (2 . "AND-LET*: an AND with local bindings, a guarded LET* special form")
    (4 . "Homogeneous numeric vector datatypes")
    (5 . "A compatible let form with signatures and rest arguments")
    (6 . "Basic String Ports")
    (7 . "Feature-based program configuration language")
    (8 . "receive: Binding to multiple values")
    (9 . "Defining Record Types")
    (10 . "#, external form")
    (11 . "Syntax for receiving multiple values")
    (13 . "String Libraries")
    (14 . "Character-set Library")
    (16 . "Syntax for procedures of variable arity")
    (17 . "Generalized set!")
    (18 . "Multithreading support")
    (19 . "Time Data Types and Procedures")
    (21 . "Real-time multithreading support")
    (22 . "Running Scheme Scripts on Unix")
    (23 . "Error reporting mechanism")
    (25 . "Multi-dimensional Array Primitives")
    (26 . "Notation for Specializing Parameters without Currying")
    (27 . "Sources of Random Bits")
    (28 . "Basic Format Strings")
    (29 . "Localization")
    (30 . "Nested Multi-line Comments")
    (31 . "A special form `rec' for recursive evaluation")
    (34 . "Exception Handling for Programs")
    (35 . "Conditions")
    (36 . "I/O Conditions")
    (37 . "args-fold: a program argument processor")
    (38 . "External Representation for Data With Shared Structure")
    (39 . "Parameter objects")
    (41 . "Streams")
    (42 . "Eager Comprehensions")
    (43 . "Vector library")
    (44 . "Collections")
    (45 . "Primitives for Expressing Iterative Lazy Algorithms")
    (46 . "Basic Syntax-rules Extensions")
    (47 . "Array")
    (48 . "Intermediate Format Strings")
    (49 . "Indentation-sensitive syntax")
    (51 . "Handling rest list")
    (54 . "Formatting")
    (55 . "require-extension")
    (57 . "Records")
    (58 . "Array Notation")
    (59 . "Vicinity")
    (60 . "Integers as Bits")
    (61 . "A more general cond clause")
    (62 . "S-expression comments")
    (63 . "Homogeneous and Heterogeneous Arrays")
    (64 . "A Scheme API for test suites")
    (66 . "Octet Vectors")
    (67 . "Compare Procedures")
    (69 . "Basic hash tables")
    (70 . "Numbers")
    (71 . "Extended LET-syntax for multiple values")
    (72 . "Hygienic macros")
    (74 . "Octet-Addressed Binary Blocks")
    (78 . "Lightweight testing")
    (86 .
        "MU and NU simulating VALUES & CALL-WITH-VALUES, and their related LET-syntax"
        )
    (87 . "=> in case clauses")
    (88 . "Keyword objects")
    (89 . "Optional positional and named parameters")
    (90 . "Extensible hash table constructor")
    (94 . "Type-Restricted Numerical Functions")
    (95 . "Sorting and Merging")
    (96 . "SLIB Prerequisites")
    (97 . "SRFI Libraries")
    (98 . "An interface to access environment variables")
    (99 . "ERR5RS Records")
    (100 . "define-lambda-object")
    (101 . "Purely Functional Random-Access Pairs and Lists")
    (105 . "Curly-infix-expressions")
    (106 . "Basic socket interface")
    (107 . "XML reader syntax")
    (108 . "Named quasi-literal constructors")
    (109 . "Extended string quasi-literals")
    (110 . "Sweet-expressions (t-expressions)")
    (111 . "Boxes")
    (112 . "Environment Inquiry")
    (113 . "Sets and bags")
    (115 . "Scheme Regular Expressions")
    (116 . "Immutable List Library")
    (117 . "Queues based on lists")
    (118 . "Simple adjustable-size strings")
    (119 . "wisp: simpler indentation-sensitive scheme")
    (120 . "Timer APIs")
    (122 . "Nonempty Intervals and Generalized Arrays")
    (123 . "Generic accessor and modifier operators")
    (124 . "Ephemerons")
    (125 . "Intermediate hash tables")
    (126 . "R6RS-based hashtables")
    (127 . "Lazy Sequences")
    (128 . "Comparators (reduced)")
    (129 . "Titlecase procedures")
    (130 . "Cursor-based string library")
    (131 . "ERR5RS Record Syntax (reduced)")
    (132 . "Sort Libraries")
    (133 . "Vector Library (R7RS-compatible)")
    (134 . "Immutable Deques")
    (135 . "Immutable Texts")
    (136 . "Extensible record types")
    (137 . "Minimal Unique Types")
    (138 . "Compiling Scheme programs to executables")
    (139 . "Syntax parameters")
    (140 . "Immutable Strings")
    (141 . "Integer division")
    (143 . "Fixnums")
    (144 . "Flonums")
    (145 . "Assumptions")
    (146 . "Mappings")
    (147 . "Custom macro transformers")
    (148 . "Eager syntax-rules")
    (149 . "Basic Syntax-rules Template Extensions")
    (150 . "Hygienic ERR5RS Record Syntax (reduced)")
    (151 . "Bitwise Operations")
    (152 . "String Library (reduced)")
    (154 . "First-class dynamic extents")
    (155 . "Promises")
    (156 . "Syntactic combiners for binary predicates")
    (157 . "Continuation marks")
    (158 . "Generators and Accumulators")
    (160 . "Homogeneous numeric vector libraries")
    (161 . "Unifiable Boxes")
    (162 . "Comparators sublibrary")
    (163 . "Enhanced array literals")
    (164 . "Enhanced multi-dimensional Arrays")
    (165 . "The Environment Monad")
    (166 . "Monadic Formatting")
    (167 . "Ordered Key Value Store")
    (168 . "Generic Tuple Store Database")
    (169 . "Underscores in numbers")
    (170 . "POSIX API")
    (171 . "Transducers")
    (172 . "Two Safer Subsets of R7RS")
    (173 . "Hooks")
    (174 . "POSIX Timespecs")
    (175 . "ASCII character library")
    (176 . "Version flag")
    (178 . "Bitvector library")
    (179 . "Nonempty Intervals and Generalized Arrays (Updated)")
    (180 . "JSON")
    (181 . "Custom ports (including transcoded ports)")
    (185 . "Linear adjustable-length strings")
    (188 . "Splicing binding constructs for syntactic keywords")
    (189 . "Maybe and Either: optional container types")
    (190 . "Coroutine Generators")
    (192 . "Port Positioning")
    (193 . "Command line")
    (194 . "Random data generators")
    (195 . "Multiple-value boxes")
    (196 . "Range Objects")
    (197 . "Pipeline Operators")
    (203 . "A Simple Picture Language in the Style of SICP")
    (207 . "String-notated bytevectors")))

;;---------------------------------------------------------------
;; Category macros

(define-reader-macro (category . xs)
  `((div (@ (class category-display))
         ,(format "Categor~a:" (match xs [(_) "ys"][_ "ies"]))
         ,@(intersperse
            "," 
            (map (lambda (x)
                  ;; we'll add link later.
                  `(a ,x))
                 xs)))))
