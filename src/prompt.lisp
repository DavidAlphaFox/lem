;;;; prompt.lisp - Lem 编辑器提示框系统
;;;;
;;;; 本文件实现 Lem 的用户输入提示系统，负责：
;;;; - 从用户获取各种类型的输入（字符串、数字、文件路径等）
;;;; - 提示框的显示和交互
;;;; - 输入历史管理
;;;;
;;;; 核心概念:
;;;; - prompt-for-*: 各种类型的提示函数
;;;; - 补全函数: 自动补全支持
;;;; - 语法表: 提示框中的文本解析
;;;;
;;;; 提示类型:
;;;;   - prompt-for-character: 单字符输入
;;;;   - prompt-for-string: 字符串输入
;;;;   - prompt-for-integer: 整数输入
;;;;   - prompt-for-buffer: 缓冲区选择
;;;;   - prompt-for-file: 文件路径选择
;;;;   - prompt-for-directory: 目录选择
;;;;   - prompt-for-command: 命令选择
;;;;
;;;; 相关文件:
;;;;   - src/ext/prompt-window.lisp: 提示窗口实现
;;;;   - src/ext/completion-mode.lisp: 补全模式
;;;;   - src/command.lisp: 命令执行

(in-package :lem-core)

;;; ============================================================================
;;; 提示框配置
;;; ============================================================================

;; 默认提示框位置（:top-display 表示显示在顶部）
(defparameter *default-prompt-gravity* :top-display
  "默认提示框位置。")

;;; ============================================================================
;;; 提示框钩子
;;; ============================================================================

;; 提示框激活时运行的钩子
(defvar *prompt-activate-hook* '()
  "提示框激活时运行的钩子。")

;; 提示框激活后运行的钩子
(defvar *prompt-after-activate-hook* '()
  "提示框激活后运行的钩子。")

;; 提示框停用时运行的钩子
(defvar *prompt-deactivate-hook* '()
  "提示框停用时运行的钩子。")

;;; ============================================================================
;;; 补全函数
;;; ============================================================================

;; 缓冲区名称补全函数
(defvar *prompt-buffer-completion-function* nil
  "缓冲区名称补全函数。")

;; 文件路径补全函数
(defvar *prompt-file-completion-function* nil
  "文件路径补全函数。")

;; 命令名称补全函数
(defvar *prompt-command-completion-function* 'completion-command
  "命令名称补全函数。")

;; 自动补全开关
(defvar *automatic-tab-completion* nil
  "当设为 t 时，补全列表立即打开。
   当设为 nil 时，用户必须按 TAB 键才能打开补全列表。")

;;; ============================================================================
;;; 提示框泛型函数
;;; ============================================================================

(defgeneric caller-of-prompt-window (prompt)
  (:documentation "返回提示框的调用者。"))

(defgeneric prompt-active-p (prompt)
  (:documentation "返回提示框是否激活。"))

(defgeneric active-prompt-window ()
  (:documentation "返回当前活动的提示窗口。"))

(defgeneric get-prompt-input-string (prompt)
  (:documentation "获取提示框中的输入字符串。"))

(defgeneric %prompt-for-character (prompt &key gravity)
  (:documentation "内部函数：提示用户输入单个字符。"))

(defgeneric %prompt-for-line (prompt &key initial-value completion-function test-function
                                          history-symbol syntax-table gravity edit-callback
                                          special-keymap use-border)
  (:documentation "内部函数：提示用户输入一行文本。"))

(defgeneric %prompt-for-file (prompt directory default existing gravity)
  (:documentation "内部函数：提示用户选择文件。"))

;;; ============================================================================
;;; 表达式前缀跳转
;;; ============================================================================

(flet ((f (c1 c2 step-fn)
         "辅助函数：检查并跳过表达式前缀字符。"
         (when c1
           (when (and (member c1 '(#\#))
                      (or (alphanumericp c2)
                          (member c2 '(#\+ #\-))))
             (funcall step-fn)))))

  (defun skip-expr-prefix-forward (point)
    "向前跳过表达式前缀（如 #+, #-）。"
    (f (character-at point 0)
       (character-at point 1)
       (lambda ()
         (character-offset point 2))))

  (defun skip-expr-prefix-backward (point)
    "向后跳过表达式前缀。"
    (f (character-at point -2)
       (character-at point -1)
       (lambda ()
         (character-offset point -2)))))

;;; ============================================================================
;;; 提示框语法表
;;; ============================================================================

(defvar *prompt-syntax-table*
  (make-syntax-table
   :space-chars '(#\space #\tab #\newline #\page)
   :symbol-chars '(#\+ #\- #\< #\> #\/ #\* #\& #\= #\. #\? #\_ #\! #\$ #\% #\: #\@ #\[ #\]
                   #\^ #\{ #\} #\~ #\# #\|)
   :paren-pairs '((#\( . #\))
                  (#\[ . #\])
                  (#\{ . #\}))
   :string-quote-chars '(#\")
   :escape-chars '(#\\)
   :fence-chars '(#\|)
   :expr-prefix-chars '(#\' #\, #\@ #\# #\`)
   :expr-prefix-forward-function 'skip-expr-prefix-forward
   :expr-prefix-backward-function 'skip-expr-prefix-backward)
  "提示框中使用的语法表。
   支持常见的 Lisp 符号字符和表达式前缀。")

;;; ============================================================================
;;; 公共提示函数
;;; ============================================================================

(defun prompt-for-character (prompt &key (gravity *default-prompt-gravity*))
  "提示用户输入单个字符。
   
   参数:
     prompt - 提示字符串
     gravity - 提示框位置（默认 :top-display）
   
   返回:
     用户输入的字符"
  (%prompt-for-character prompt :gravity gravity))

(defun prompt-for-y-or-n-p (prompt &key (gravity *default-prompt-gravity*))
  "提示用户输入 y 或 n 进行确认。
   
   参数:
     prompt - 提示字符串
   
   返回:
     t（用户输入 y）或 nil（用户输入 n）"
  (loop :for c := (prompt-for-character (format nil "~A [y/n]? " prompt) :gravity gravity)
        :do (case c
              (#\y (return t))
              (#\n (return nil)))))

(defun prompt-for-string (prompt &rest args
                                 &key initial-value
                                      completion-function
                                      test-function
                                      (history-symbol nil)
                                      (syntax-table (current-syntax))
                                      (gravity *default-prompt-gravity*)
                                      edit-callback
                                      special-keymap
                                      use-border)
  "提示用户输入字符串。
   
   参数:
     prompt - 提示字符串
     initial-value - 初始值（可选）
     completion-function - 补全函数（可选）
     test-function - 输入验证函数（可选）
     history-symbol - 历史记录符号（可选）
     syntax-table - 语法表（默认当前语法表）
     gravity - 提示框位置
     edit-callback - 编辑回调函数（可选）
     special-keymap - 特殊键映射（可选）
     use-border - 是否使用边框
   
   返回:
     用户输入的字符串"
  (declare (ignore initial-value
                   completion-function
                   test-function
                   history-symbol
                   syntax-table
                   gravity
                   edit-callback
                   special-keymap
                   use-border))
  (apply #'%prompt-for-line prompt args))

(defun prompt-for-integer (prompt &key initial-value min max (gravity *default-prompt-gravity*))
  "提示用户输入整数。
   
   参数:
     prompt - 提示字符串
     initial-value - 初始值（可选）
     min - 最小值（可选）
     max - 最大值（可选）
     gravity - 提示框位置
   
   返回:
     用户输入的整数"
  (check-type initial-value (or null integer))
  (parse-integer
   (prompt-for-string prompt
                      :initial-value (when initial-value (princ-to-string initial-value))
                      :test-function (lambda (str)
                                       (multiple-value-bind (n len)
                                           (parse-integer str :junk-allowed t)
                                         (and
                                          n
                                          (/= 0 (length str))
                                          (= (length str) len)
                                          (if min (<= min n) t)
                                          (if max (<= n max) t))))
                      :history-symbol 'prompt-for-integer
                      :gravity gravity)))

(defun prompt-for-buffer (prompt &key default existing (gravity *default-prompt-gravity*))
  "提示用户选择缓冲区。
   
   参数:
     prompt - 提示字符串
     default - 默认值（可选）
     existing - 是否要求缓冲区必须存在
     gravity - 提示框位置
   
   返回:
     缓冲区名称字符串"
  (let ((result (prompt-for-string
                 (if default
                     (format nil "~a(~a) " prompt default)
                     prompt)
                 :completion-function *prompt-buffer-completion-function*
                 :test-function (and existing
                                     (lambda (name)
                                       (or (alexandria:emptyp name)
                                           (get-buffer name))))
                 :history-symbol 'prompt-for-buffer
                 :gravity gravity)))
    (if (string= result "")
        default
        result)))

(defun prompt-for-file (prompt &key directory (default (buffer-directory)) existing
                                    (gravity *default-prompt-gravity*))
  "提示用户选择文件。
   
   参数:
     prompt - 提示字符串
     directory - 起始目录
     default - 默认值
     existing - 是否要求文件必须存在
     gravity - 提示框位置
   
   返回:
     文件路径字符串"
  (%prompt-for-file prompt directory default existing gravity))

(defun prompt-for-directory (prompt &rest args
                                    &key directory (default (buffer-directory)) existing
                                    &allow-other-keys)
  "提示用户选择目录。
   
   参数:
     prompt - 提示字符串
     directory - 起始目录
     default - 默认值
     existing - 是否要求目录必须存在
   
   返回:
     目录路径字符串"
  (let ((result
          (apply #'prompt-for-string
                 prompt
                 :initial-value directory
                 :completion-function
                 (when *prompt-file-completion-function*
                   (lambda (str)
                     (funcall *prompt-file-completion-function*
                              (if (alexandria:emptyp str)
                                  "./"
                                  str)
                              directory :directory-only t)))
                 :test-function (and existing #'virtual-probe-file)
                 :history-symbol 'prompt-for-directory
                 (alexandria:remove-from-plist args :directory :default :existing))))
    (if (string= result "")
        default
        result)))

;;; ============================================================================
;;; 命令补全
;;; ============================================================================

(defun completion-command (str)
  "命令名称补全函数。
   
   参数:
     str - 当前输入的字符串
   
   返回:
     匹配的命令名称列表"
  (sort
   (if (find #\- str)
       (completion-hyphen str (all-command-names))
       (completion str (all-command-names)))
   #'string-lessp))

(defun prompt-for-command (prompt &key candidates)
  "提示用户输入命令。
   
   参数:
     prompt - 提示字符串
     candidates - 候选命令列表（可选）
   
   返回:
     命令名称字符串"
  (prompt-for-string
   prompt
   :completion-function (if candidates
                            (lambda (input)
                              (funcall *prompt-command-completion-function* input :candidates candidates))
                            *prompt-command-completion-function*)
   :test-function 'exist-command-p
   :history-symbol 'mh-execute-command
   :syntax-table *prompt-syntax-table*))

;;; ============================================================================
;;; 特殊提示
;;; ============================================================================

(defun prompt-for-library (prompt &key history-symbol)
  "提示用户选择 Lem 库/扩展。
   
   参数:
     prompt - 提示字符串
     history-symbol - 历史记录符号（可选）
   
   返回:
     库系统名称"
  (macrolet ((ql-symbol-value (symbol)
               `(symbol-value (uiop:find-symbol* ,symbol :quicklisp))))
    (let ((systems
            (append
             (mapcar (lambda (x) (pathname-name x))
                     (directory
                      (merge-pathnames "**/lem-*.asd"
                                       (asdf:system-source-directory :lem-contrib))))
             (set-difference
              (mapcar #'pathname-name
                      (loop for i in (ql-symbol-value :*local-project-directories*)
                            append (directory (merge-pathnames "**/lem-*.asd" i))))
              (mapcar #'pathname-name
                      (directory (merge-pathnames "**/lem-*.asd"
                                                  (asdf:system-source-directory :lem))))
              :test #'equal))))
      (setq systems (mapcar (lambda (x) (subseq x 4)) systems))
      (prompt-for-string prompt
                         :completion-function (lambda (str) (completion str systems))
                         :test-function (lambda (system) (find system systems :test #'string=))
                         :history-symbol history-symbol))))

(defun prompt-for-encodings (prompt &key history-symbol)
  "提示用户选择编码。
   
   参数:
     prompt - 提示字符串
     history-symbol - 历史记录符号（可选）
   
   返回:
     编码关键字"
  (let ((encodings (encodings)))
    (let ((name (prompt-for-string
                 (format nil "~A(~(~A~))" prompt *default-external-format*)
                 :completion-function (lambda (str) (completion str encodings))
                 :test-function (lambda (encoding) (or (equal encoding "")
                                                       (find encoding encodings :test #'string=)))
                 :history-symbol history-symbol)))
      (cond ((equal name "") *default-external-format*)
            (t (read-from-string (format nil ":~A" name)))))))
