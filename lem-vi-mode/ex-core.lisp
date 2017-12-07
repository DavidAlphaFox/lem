(defpackage :lem-vi-mode.ex-core
  (:use :cl)
  (:export :*point*
           :syntax-error
           :search-forward
           :search-backward
           :goto-line
           :current-line
           :last-line
           :marker
           :offset-line
           :goto-current-point
           :range
           :all-lines
           :call-ex-command
           :define-ex-command))
(in-package :lem-vi-mode.ex-core)

(defvar *point*)
(defvar *command-table* '())

(defun syntax-error ()
  (lem:editor-error "syntax error"))

(defun search-forward (pattern)
  (lem:search-forward-regexp *point* pattern))

(defun search-backward (pattern)
  (lem:search-backward-regexp *point* pattern))

(defun goto-line (line-number)
  (lem:move-to-line (copy-point *point* :temporary) line-number))

(defun current-line ()
  *point*)

(defun last-line ()
  (lem:buffer-end *point*))

(defun marker (char)
  (declare (ignore char)))

(defun offset-line (offset)
  (declare (ignore offset)))

(defun goto-current-point (range)
  (declare (ignore range)))

(defun range (&rest range)
  range)

(defun all-lines ()
  (let ((buffer (lem:point-buffer *point*)))
    (list (lem:copy-point (lem:buffer-start-point buffer) :temporary)
          (lem:copy-point (lem:buffer-end-point buffer) :temporary))))

(defun call-ex-command (range command argument)
  (let ((function (find-ex-command command)))
    (unless function
      (lem:editor-error "unknown command: ~A" command))
    (funcall function range argument)))

(defun find-ex-command (command)
  (loop :for (names function) :in *command-table*
        :do (when (member command names :test #'string=)
              (return function))))

(defmacro define-ex-command (names (range argument) &body body)
  `(push (list (list . ,(alexandria:ensure-list names)) (lambda (,range ,argument) ,@body))
         *command-table*))
