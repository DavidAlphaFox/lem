(in-package :lem)

(export '(*enable-recursive-minibuffers*
          *minibuffer-completion-function*
          *minibuffer-activate-hook*
          *minibuffer-deactivate-hook*
          *minibuf-keymap*
          minibuffer-prompt-attribute
          minibuffer-window-p
          minibuffer-window-active-p
          minibufferp
          message
          message-without-log
          message-buffer
          check-switch-minibuffer-window
          minibuffer-read-line-execute
          minibuffer-read-line-completion
          minibuffer-read-line-prev-history
          minibuffer-read-line-next-history))

(defconstant +minibuffer-window-height+ 1)
(defvar *enable-recursive-minibuffers* nil)

(defvar +recursive-minibuffer-break-tag+ (gensym))

(defvar *minibuffer-completion-function* nil)

(defvar *minibuffer-activate-hook* '())
(defvar *minibuffer-deactivate-hook* '())

(defclass sticky-prompt ()
  ((minibuffer-buffer
    :initarg :minibuffer-buffer
    :initform nil
    :accessor sticky-prompt-minibuffer-buffer)
   (echoarea-buffer
    :initarg :echoarea-buffer
    :initform nil
    :accessor sticky-prompt-echoarea-buffer)
   (minibuffer-window
    :initarg :minibuffer-window
    :initform nil
    :accessor sticky-prompt-minibuffer-window)
   (caller-of-prompt-window
    :initarg :caller-of-prompt-window
    :initform nil
    :accessor sticky-prompt-caller-of-prompt-window)
   (minibuffer-start-charpos
    :initarg :minibuffer-start-charpos
    :initform nil
    :accessor sticky-prompt-minibuffer-start-charpos)))

(defclass sticky-minibuffer-window (floating-window) ())

(defun make-minibuffer-window (frame buffer)
  (make-instance 'sticky-minibuffer-window
                 :buffer buffer
                 :x 0
                 :y (- (display-height)
                       +minibuffer-window-height+)
                 :width (display-width)
                 :height +minibuffer-window-height+
                 :use-modeline-p nil
                 :frame frame))

(defmethod prompt-start-point ((prompt sticky-prompt))
  (character-offset
   (copy-point (buffer-start-point (minibuffer))
               :temporary)
   (sticky-prompt-minibuffer-start-charpos prompt)))

(defmethod caller-of-prompt-window ((prompt sticky-prompt))
  (sticky-prompt-caller-of-prompt-window prompt))

(defmethod prompt-active-p ((prompt sticky-prompt))
  (eq (sticky-prompt-minibuffer-window prompt)
      (current-window)))

(define-attribute minibuffer-prompt-attribute
  (t :foreground "blue" :bold-p t))

(defun minibuffer-window ()
  (when (frame-minibuffer (current-frame))
    (sticky-prompt-minibuffer-window (frame-minibuffer (current-frame)))))
(defun minibuffer-window-p (window)
  (typep window 'sticky-minibuffer-window))
(defun minibuffer-window-active-p () (eq (current-window) (minibuffer-window)))
(defun minibuffer () (window-buffer (minibuffer-window)))
(defun minibufferp (buffer) (eq buffer (minibuffer)))

(define-major-mode minibuffer-mode nil
    (:name "minibuffer"
     :keymap *minibuf-keymap*
     :syntax-table (make-syntax-table
                    :symbol-chars '(#\_ #\-)))
  (setf (variable-value 'truncate-lines :buffer (current-buffer)) nil))

(defun create-minibuffer (frame)
  (let* ((echoarea-buffer
           (make-buffer "*echoarea*" :temporary t :enable-undo-p nil))
         (minibuffer-buffer
           (make-buffer "*minibuffer*" :temporary t :enable-undo-p t))
         (minibuffer-window
           (make-minibuffer-window frame echoarea-buffer)))
    (make-instance 'sticky-prompt
                   :minibuffer-buffer minibuffer-buffer
                   :echoarea-buffer echoarea-buffer
                   :minibuffer-window minibuffer-window)))

(defun teardown-minibuffer (sticky-prompt)
  (%free-window (sticky-prompt-minibuffer-window sticky-prompt)))

(defun minibuf-update-size ()
  (when (frame-minibuffer (current-frame))
    (window-set-pos (minibuffer-window) 0 (1- (display-height)))
    (window-set-size (minibuffer-window) (display-width) 1)))

(defmethod show-message (string)
  (let ((sticky-prompt (frame-minibuffer (current-frame))))
    (cond (string
           (erase-buffer (sticky-prompt-echoarea-buffer sticky-prompt))
           (let ((point (buffer-point (sticky-prompt-echoarea-buffer sticky-prompt))))
             (insert-string point string))
           (when (active-minibuffer-window)
             (handler-case
                 (with-current-window (minibuffer-window)
                   (unwind-protect
                        (progn
                          (%switch-to-buffer (sticky-prompt-echoarea-buffer sticky-prompt)
                                             nil nil)
                          (sit-for 1 t))
                     (%switch-to-buffer (sticky-prompt-minibuffer-buffer sticky-prompt)
                                        nil nil)))
               (editor-abort ()
                 (minibuf-read-line-break)))))
          (t
           (erase-buffer (sticky-prompt-echoarea-buffer sticky-prompt))))))

(defmethod show-message-buffer (buffer)
  (let ((sticky-prompt (frame-minibuffer (current-frame))))
    (erase-buffer (sticky-prompt-echoarea-buffer sticky-prompt))
    (insert-buffer (buffer-point (sticky-prompt-echoarea-buffer sticky-prompt)) buffer)))

(defmethod prompt-for-character (prompt-string)
  (when (interactive-p)
    (message "~A" prompt-string)
    (redraw-display))
  (let ((key (read-key)))
    (when (interactive-p)
      (message nil))
    (if (abort-key-p key)
        (error 'editor-abort)
        (key-to-char key))))

(define-key *minibuf-keymap* "C-j" 'minibuffer-read-line-execute)
(define-key *minibuf-keymap* "Return" 'minibuffer-read-line-execute)
(define-key *minibuf-keymap* "Tab" 'minibuffer-read-line-completion)
(define-key *minibuf-keymap* "M-p" 'minibuffer-read-line-prev-history)
(define-key *minibuf-keymap* "M-n" 'minibuffer-read-line-next-history)
(define-key *minibuf-keymap* "C-g" 'minibuf-read-line-break)

(defvar *minibuf-read-line-comp-f*)
(defvar *minibuf-read-line-existing-p*)

(defvar *minibuf-read-line-history-table* (make-hash-table))
(defvar *minibuf-read-line-history*)

(defvar *minibuf-read-line-depth* 0)
(defvar *minibuf-prev-prompt* nil)

(defun check-switch-minibuffer-window ()
  (when (minibuffer-window-active-p)
    (editor-error "Cannot switch buffer in minibuffer window")))

(defmethod active-minibuffer-window ()
  (if (/= 0 *minibuf-read-line-depth*)
      (minibuffer-window)
      nil))

(defun minibuffer-start-point ()
  (prompt-start-point (frame-minibuffer (current-frame))))

(defun get-minibuffer-string ()
  (points-to-string (minibuffer-start-point)
                    (buffer-end-point (minibuffer))))

(defun minibuffer-clear-input ()
  (delete-between-points (minibuffer-start-point)
                         (buffer-end-point (minibuffer))))

(define-command minibuffer-read-line-execute () ()
  (let ((str (get-minibuffer-string)))
    (when (or (null *minibuf-read-line-existing-p*)
              (funcall *minibuf-read-line-existing-p* str))
      (throw 'minibuf-read-line-end t)))
  t)

(define-command minibuffer-read-line-completion () ()
  (when (and *minibuf-read-line-comp-f*
             *minibuffer-completion-function*)
    (with-point ((start (minibuffer-start-point)))
      (funcall *minibuffer-completion-function*
               *minibuf-read-line-comp-f*
               start))))

(defun %backup-edit-string (history)
  (lem.history:backup-edit-string
   history
   (points-to-string (minibuffer-start-point)
                     (buffer-end-point (minibuffer)))))

(defun %restore-edit-string (history)
  (multiple-value-bind (str win)
      (lem.history:restore-edit-string history)
    (when win
      (minibuffer-clear-input)
      (insert-string (current-point) str))))

(define-command minibuffer-read-line-prev-history () ()
  (%backup-edit-string *minibuf-read-line-history*)
  (multiple-value-bind (str win)
      (lem.history:prev-history *minibuf-read-line-history*)
    (when win
      (minibuffer-clear-input)
      (insert-string (current-point) str))))

(define-command minibuffer-read-line-next-history () ()
  (%backup-edit-string *minibuf-read-line-history*)
  (%restore-edit-string *minibuf-read-line-history*)
  (multiple-value-bind (str win)
      (lem.history:next-history *minibuf-read-line-history*)
    (when win
      (minibuffer-clear-input)
      (insert-string (current-point) str))))

(define-command minibuf-read-line-break () ()
  (throw +recursive-minibuffer-break-tag+
    +recursive-minibuffer-break-tag+))

(defun minibuf-read-line-loop (comp-f existing-p syntax-table)
  (let ((*minibuf-read-line-existing-p* existing-p)
        (*minibuf-read-line-comp-f* comp-f))
    (with-current-syntax syntax-table
      (catch 'minibuf-read-line-end
        (command-loop))
      (let ((str (get-minibuffer-string)))
        (lem.history:add-history *minibuf-read-line-history* str)
        str))))

(defmethod prompt-for-line (prompt initial comp-f existing-p history-name
                            &optional (syntax-table (current-syntax)))
  (when (= 0 *minibuf-read-line-depth*)
    (run-hooks *minibuffer-activate-hook*))
  (when (and (not *enable-recursive-minibuffers*) (< 0 *minibuf-read-line-depth*))
    (editor-error "ERROR: recursive use of minibuffer"))
  (let* ((frame (current-frame))
         (sticky-prompt (frame-minibuffer frame))
         (caller-of-prompt-window (sticky-prompt-caller-of-prompt-window sticky-prompt)))
    (unwind-protect
         (progn
           (setf (sticky-prompt-caller-of-prompt-window sticky-prompt) (current-window))
           (let ((*minibuf-read-line-history*
                   (let ((table (gethash history-name *minibuf-read-line-history-table*)))
                     (or table
                         (setf (gethash history-name *minibuf-read-line-history-table*)
                               (lem.history:make-history))))))
             (let ((result
                     (catch +recursive-minibuffer-break-tag+
                       (handler-case
                           (with-current-window (minibuffer-window)
                             (%switch-to-buffer (sticky-prompt-minibuffer-buffer sticky-prompt)
                                                nil nil)
                             (let ((minibuf-buffer-prev-string
                                     (points-to-string (buffer-start-point (minibuffer))
                                                       (buffer-end-point (minibuffer))))
                                   (prev-prompt-length
                                     (when *minibuf-prev-prompt*
                                       (length *minibuf-prev-prompt*)))
                                   (minibuf-buffer-prev-point
                                     (window-point (minibuffer-window)))
                                   (*minibuf-prev-prompt* prompt)
                                   (*minibuf-read-line-depth*
                                     (1+ *minibuf-read-line-depth*)))
                               (let ((*inhibit-read-only* t))
                                 (erase-buffer))
                               (minibuffer-mode)
                               (reset-horizontal-scroll (minibuffer-window))
                               (unless (string= "" prompt)
                                 (insert-string (current-point) prompt
                                                :attribute 'minibuffer-prompt-attribute
                                                :read-only t
                                                :field t)
                                 (character-offset (current-point) (length prompt)))
                               (let ((start-charpos (sticky-prompt-minibuffer-start-charpos sticky-prompt)))
                                 (unwind-protect
                                      (progn
                                        (setf (sticky-prompt-minibuffer-start-charpos sticky-prompt)
                                              (point-charpos (current-point)))
                                        (when initial
                                          (insert-string (current-point) initial))
                                        (unwind-protect (minibuf-read-line-loop comp-f existing-p syntax-table)
                                          (if (deleted-window-p (sticky-prompt-caller-of-prompt-window sticky-prompt))
                                              (setf (current-window) (car (window-list)))
                                              (setf (current-window) (sticky-prompt-caller-of-prompt-window sticky-prompt)))
                                          (with-current-window (minibuffer-window)
                                            (let ((*inhibit-read-only* t))
                                              (erase-buffer))
                                            (insert-string (current-point) minibuf-buffer-prev-string)
                                            (when prev-prompt-length
                                              (with-point ((start (current-point))
                                                           (end (current-point)))
                                                (line-start start)
                                                (line-offset end 0 prev-prompt-length)
                                                (put-text-property start end
                                                                   :attribute 'minibuffer-prompt-attribute)
                                                (put-text-property start end :read-only t)
                                                (put-text-property start end :field t)))
                                            (move-point (current-point) minibuf-buffer-prev-point)
                                            (when (= 1 *minibuf-read-line-depth*)
                                              (run-hooks *minibuffer-deactivate-hook*)
                                              (%switch-to-buffer (sticky-prompt-echoarea-buffer sticky-prompt) nil nil)))))
                                   (setf (sticky-prompt-minibuffer-start-charpos sticky-prompt) start-charpos)))))
                         (editor-abort (c)
                           (error c))))))
               (if (eq result +recursive-minibuffer-break-tag+)
                   (error 'editor-abort)
                   result))))
      (setf (sticky-prompt-caller-of-prompt-window sticky-prompt) caller-of-prompt-window))))
