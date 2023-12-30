(defparameter *total-changes* 0)
(defparameter *file-changes* 0)
(defparameter *dry-run* nil)
(defparameter *changed* nil)

(defun symbol-or-number (s)
  (or (symbolp s) (numberp s)))

(defun fixproof-equal (s1 s2)
  (and (symbolp s1)
       (string-equal s1 s2)))

;; s --> "s"
(defun fixproof-symbol (s &key but test)
  (let ((test (or test #'symbolp))
	(but  (if (listp but) but (list but))))
    (if (and  (funcall test s) (not (member s but)))
	(progn (incf *file-changes*) (setq *changed* t) (format nil "~s" s))
      s)))

;; s | (s1 .. sn) --> "s" | ("s1" .. "sn")
(defun fixproof-symbol-or-symbols (s &key but test)
  (if (listp s)
      (mapcar #'(lambda (x) (fixproof-symbol x :but but :test test)) s)
    (fixproof-symbol s :but but :test test)))

;; (step NAME ..) --> (step "name" ..)
;; (LEMMA NAME &OPTIONAL SUBST)
;; (USE/$ LEMMA-NAME &OPTIONAL SUBST (IF-MATCH BEST) (INSTANTIATOR INST?) ...)
;; (REWRITE/$ LEMMA-OR-FNUM &OPTIONAL (FNUMS *) SUBST (TARGET-FNUMS *) ...)
;; (EXPAND FUNCTION-NAME &OPTIONAL (FNUM *) OCCURRENCE ...)
;; (INDUCT/$ VAR &OPTIONAL (FNUM 1) NAME)
;; (LABEL LABEL FNUMS &OPTIONAL PUSH?)
(defun fix-name (s-expr) 
  (cons (car s-expr)
	(cons (fixproof-symbol (cadr s-expr))
	      (cddr s-expr))))

;; (step NAME1 .. NAMEN) --> (step "name1" .. "namen")
;; (EXPAND*/$ &REST NAMES)
;; (AUTO-REWRITE &REST NAMES)
;; (CASE &REST FORMULAS)
;; (HIDE &REST FNUMS)
(defun fix-names (s-expr &key but)
  (cons (car s-expr)
	(mapcar #'(lambda (s) (fixproof-symbol s :but but))
		(cdr s-expr))))

;; (step NAME | (NAME1 .. NAMEN)) --> (step "name1" .. "namen")
;; (TYPEPRED &REST EXPRS)
(defun fix-name-or-names (s-expr)
  (cons (car s-expr)
	(let ((rest (if (listp (cadr s-expr)) (cadr s-expr) (cdr s-expr))))
	  (mapcar #'fixproof-symbol
		  rest))))

;; (step FNUM NAME1 .. NAMEN) --> (step fnum "name1" .. "namen")
;; (INST/$ FNUM &REST TERMS)
;; (INST-CP/$ FNUM &REST TERMS)
(defun fix-fnum-names-or-numbers (s-expr)
  (cons (car s-expr)
	(cons (cadr s-expr)
	      (mapcar #'(lambda (s) (fixproof-symbol s :but '_ :test #'symbol-or-number))
		      (cddr s-expr)))))

;; (step FNUM NAME | (NAME1 .. NAMEN) ..) --> (step fnum "name | ("name1" .. "namen") ..)
;; (SKOLEM FNUM CONSTANTS &OPTIONAL SKOLEM-TYPEPREDS? DONT-SIMPLIFY?)
(defun fix-fnum-name-or-names (s-expr)
  (cons (car s-expr)
	(cons (cadr s-expr)
	      (cons (fixproof-symbol-or-symbols (caddr s-expr))
		    (cdddr s-expr)))))


;; (step NAME NAME | (NAME1 .. NAMEN) ..) --> (step name "name | ("name1" .. "namen") ..)
;; (MEASURE-INDUCT/$ MEASURE VARS &OPTIONAL (FNUM 1) ORDER SKOLEM-TYPEPREDS?)
(defun fix-name-name-or-names (s-expr)
  (cons (car s-expr)
	(cons (fixproof-symbol (cadr s-expr))
	      (cons (fixproof-symbol-or-symbols (caddr s-expr))
		    (cdddr s-expr)))))

;; (step NAME NAME ..) --> (step "name" "name" ..)
;; (GENERALIZE/$ TERM VAR &OPTIONAL GTYPE (FNUMS *) (SUBTERMS-ONLY? T))
;; (NAME-REPLACE/$ RNAME EXPR &OPTIONAL (HIDE? T) &KEY (FNUMS *) ..)
(defun fix-name-name-or-number (s-expr &key test) 
  (cons (car s-expr)
	(cons (fixproof-symbol (cadr s-expr))
	      (cons (fixproof-symbol (caddr s-expr) :test test)
		    (cdddr s-expr)))))

(defmacro do-fix (s-expr fix)
  (let ((sym (gensym)))
    `(let* ((*changed* nil)
	    (,sym ,fix))
       (if (and *changed* *dry-run*)
	   (or (format t "~%~s --> ~s" ,s-expr ,sym) ,s-expr)
	 ,sym))))

(defun fix-proofs (s-expr)
  (if (listp s-expr)
      (cond ((member (car s-expr) '("lemma" "use" "rewrite" "expand" "induct" "label") :test #'fixproof-equal)
	     (do-fix s-expr (fix-name s-expr)))
	    ((member (car s-expr) '("expand*" "case" "auto-rewrite") :test #'fixproof-equal)
	     (do-fix s-expr (fix-names s-expr)))
	    ((member (car s-expr) '("hide") :test #'fixproof-equal)
	     (do-fix s-expr (fix-names s-expr :but '(+ - *))))
	    ((member (car s-expr) '("typepred") :test #'fixproof-equal)
	     (do-fix s-expr (fix-name-or-names s-expr)))
	    ((member (car s-expr) '("inst" "inst-cp") :test #'fixproof-equal) 
	     (do-fix s-expr (fix-fnum-names-or-numbers s-expr)))
	    ((member (car s-expr) '("skolem") :test #'fixproof-equal)
	     (do-fix s-expr (fix-fnum-name-or-names s-expr)))
	    ((member (car s-expr) '("measure-induct") :test #'fixproof-equal)
	     (do-fix s-expr (fix-name-name-or-names s-expr)))
	    ((member (car s-expr) '("generalize") :test #'fixproof-equal) 
	     (do-fix s-expr (fix-name-name-or-number s-expr)))
	    ((member (car s-expr) '("name-replace") :test #'fixproof-equal)
	     (do-fix s-expr (fix-name-name-or-number s-expr :test #'symbol-or-number)))
	    (t (mapcar #'fix-proofs s-expr)))
    s-expr))

(defun fix-file (name &key dry-run)
  (let* ((*file-changes* 0)
	 (*dry-run* dry-run)
	 (in-name name)
	 (out-name (format nil "~a.new" in-name)))
    (with-open-file
     (in-file (merge-pathnames in-name) :direction :input)
     (when in-file
       (format t "Fixing proofs in ~a " (file-namestring name))
       (with-open-file
	(out-file (merge-pathnames out-name) :direction :output
		  :if-exists :supersede)
	(let ((s-expr (read in-file nil)))
	  (when s-expr
	    (format out-file "~s" (fix-proofs s-expr)))))
       (format t "[~a change~:p]~%" *file-changes*)
       (incf *total-changes* *file-changes*)))))

(defun fix-files (names &key dry-run)
  (let ((names (if (listp names) names (list names))))
    (loop for name in names
	  do (fix-file name :dry-run dry-run)))
  (format t "Total Changes: ~a~%" *total-changes*))
