;;;; defcommand.lisp - Lem 编辑器命令系统
;;;;
;;;; 本文件实现 Lem 的交互式命令定义系统。
;;;; 命令是用户可通过 M-x 或键绑定调用的操作。
;;;;
;;;; 核心概念:
;;;; - define-command: 定义交互式命令的宏
;;;; - 参数描述符: 声明命令如何获取参数
;;;; - primary-command: 命令基类
;;;;
;;;; 参数描述符类型:
;;;;   :universal (p)     - 通用参数（前缀参数），默认 1
;;;;   :universal-nil (P) - 通用参数，默认 nil
;;;;   :string (s)        - 提示用户输入字符串
;;;;   :number (n)        - 提示用户输入数字
;;;;   :buffer (b)        - 提示选择缓冲区
;;;;   :other-buffer (B)  - 提示选择其他缓冲区
;;;;   :file (f)          - 提示选择文件
;;;;   :new-file (F)      - 提示输入新文件名
;;;;   :region (r)        - 传递区域起点和终点
;;;;   :splice            - 插入自定义代码
;;;;
;;;; 相关文件:
;;;;   - src/command.lisp: 命令执行和查找
;;;;   - src/keymap.lisp: 键绑定到命令
;;;;   - src/interp.lisp: 命令循环

(in-package :lem-core)

;;; ============================================================================
;;; 警告收集
;;; ============================================================================

;; 编辑器警告列表（用于收集弃用警告等）
(defvar *editor-warnings* '())

(eval-when (:compile-toplevel :load-toplevel)
  (defun editor-warning (fmt &rest args)
    "记录编辑器警告信息。
     警告会在初始化后显示在 *EDITOR WARNINGS* 缓冲区中。"
    (push (apply #'format nil fmt args) *editor-warnings*)
    (values))

;;; ============================================================================
;;; 参数描述符解析
;;; ============================================================================

  (defun parse-arg-descriptors (arg-descriptors universal-argument)
    "解析命令参数描述符。
     
     参数描述符声明命令如何获取参数值。
     支持两种格式：
       - 新格式: (:string \"Prompt: \"), (:universal), (:file \"File: \")
       - 旧格式: \"sPrompt: \", \"p\", \"fFile: \"（已弃用）
     
     参数:
       arg-descriptors: 描述符列表
       universal-argument: 通用参数变量名
     
     返回:
       生成参数列表的表达式
     
     描述符类型:
       :universal / :universal-1 -> 通用参数，默认 1
       :universal-nil           -> 通用参数，默认 nil
       :string                  -> 提示输入字符串
       :number                  -> 提示输入整数
       :buffer                  -> 提示选择缓冲区
       :other-buffer            -> 提示选择其他缓冲区
       :file                    -> 提示选择现有文件
       :new-file                -> 提示输入新文件名
       :region                  -> 传递区域起点和终点
       :splice                  -> 插入自定义代码返回值"
    (let* ((pre-forms '())
           (forms
             (mapcar
              (lambda (arg-descriptor)
                (setf arg-descriptor (cond ((and (stringp arg-descriptor)
                                                 (< 0 (length arg-descriptor)))
                                            (editor-warning "define-command: Deprecated expression (~A) is used for arg-descriptor" arg-descriptor)
                                            (list (ecase (char arg-descriptor 0)
                                                    (#\p :universal) (#\P :universal-nil)
                                                    (#\s :string) (#\n :number)
                                                    (#\b :buffer) (#\B :other-buffer)
                                                    (#\f :file) (#\F :new-file)
                                                    (#\r :region))
                                                  (subseq arg-descriptor 1)))
                                           ((symbolp arg-descriptor)
                                            (list arg-descriptor))
                                           (t arg-descriptor)))
                (or (and (consp arg-descriptor)
                         (case (first arg-descriptor)
                           (:splice
                            (assert (alexandria:length= arg-descriptor 2))
                            (second arg-descriptor))
                           ((:universal :universal-1) `(list (or ,universal-argument 1)))
                           (:universal-nil `(list ,universal-argument))
                           (:string `(list (prompt-for-string ,(second arg-descriptor))))
                           (:number
                            `(list (prompt-for-integer ,(second arg-descriptor))))
                           (:buffer
                            `(list (prompt-for-buffer
                                    ,(second arg-descriptor)
                                    :default (if (attached-buffer-p (current-buffer))
                                                 (buffer-name (attached-buffer-parent-buffer (current-buffer)))
                                                 (buffer-name (current-buffer)))
                                    :existing t)))
                           (:other-buffer
                            `(list (prompt-for-buffer ,(second arg-descriptor)
                                                      :default (buffer-name (other-buffer))
                                                      :existing nil)))
                           (:file
                            `(list (prompt-for-file
                                    ,(second arg-descriptor)
                                    :directory (buffer-directory)
                                    :default nil
                                    :existing t)))
                           (:new-file
                            `(list (prompt-for-file
                                    ,(second arg-descriptor)
                                    :directory (buffer-directory)
                                    :default nil
                                    :existing nil)))
                           (:region
                            (push '(check-marked) pre-forms)
                            '(list (region-beginning-using-global-mode
                                    (current-global-mode))
                              (region-end-using-global-mode (current-global-mode))))))
                    `(multiple-value-list ,arg-descriptor)))
              arg-descriptors)))
      (if (null pre-forms)
          `(append ,@forms)
          `(progn
             ,@pre-forms
             (append ,@forms)))))

  (alexandria:with-unique-names (arguments)
    (defun gen-defcommand-body (fn-name
                                universal-argument
                                arg-descriptors)
      `(block ,fn-name
         (destructuring-bind (&rest ,arguments)
             ,(parse-arg-descriptors arg-descriptors universal-argument)
           (apply #',fn-name ,arguments))))))

;;; ============================================================================
;;; 命令注册
;;; ============================================================================

(defun check-already-defined-command (name source-location)
  "检查命令是否已在其他文件中定义（仅 SBCL）。
   如果已定义，发出继续/中断错误。"
  #+sbcl
  (alexandria:when-let* ((command (get-command name))
                         (command-source-location (command-source-location command)))
    (unless (equal (sb-c:definition-source-location-namestring command-source-location)
                   (sb-c:definition-source-location-namestring source-location))
      (cerror "continue"
              "~A is already defined in another file ~A"
              name
              (sb-c:definition-source-location-namestring (command-source-location command))))))

(defun register-command (command &key mode-name command-name)
  "注册命令到全局命令表。
   
   参数:
     command: 命令实例
     mode-name: 关联的模式名称（可选）
     command-name: 命令字符串名称（用于 M-x）"
  (when mode-name
    (associate-command-with-mode mode-name command))
  (add-command command-name command))

;;; ============================================================================
;;; define-command 宏
;;; ============================================================================

(defmacro define-command (name-and-options params (&rest arg-descriptors) &body body)
  "定义交互式命令。
   
   命令可通过以下方式调用:
     - M-x 命令名
     - 键绑定
     - 程序调用
   
   基本示例:
     (define-command write-hello () ()
       (insert-string (current-point) \"hello\"))
   
   带通用参数的命令:
     (define-command write-hellos (n) (:universal)
       (dotimes (i n)
         (insert-string (current-point) \"hello \")))
     
     调用: C-u 3 M-x write-hellos RET
   
   参数描述符:
     :universal (p)       - 通用参数，默认 1
     :universal-nil (P)   - 通用参数，默认 nil
     :string (s)          - 提示输入字符串
     :number (n)          - 提示输入整数
     :buffer (b)          - 提示选择缓冲区
     :other-buffer (B)    - 提示选择其他缓冲区
     :file (f)            - 提示选择文件
     :new-file (F)        - 提示输入新文件名
     :region (r)          - 传递区域起点和终点（需要两个参数）
     :splice              - 插入自定义代码
   
   选项:
     (:class class-name)  - 指定命令类名
     (:name \"cmd-name\")  - 指定 M-x 中的命令名
     (:mode mode-name)    - 关联到模式
     (:advice-classes)    - 指定 advice 类
   
   字符串提示示例:
     (define-command find-file (filename) ((:file \"Find file: \"))
       (find-file filename))
   
   区域操作示例:
     (define-command upcase-region (start end) (:region)
       (uppercase-region start end))"
  (destructuring-bind (name . options) (uiop:ensure-list name-and-options)
    (let ((advice-classes (alexandria:assoc-value options :advice-classes))
          (class-name (alexandria:if-let (elt (assoc :class options))
                        (second elt)
                        name))
          (command-name (alexandria:if-let (elt (assoc :name options))
                          (second elt)
                          (string-downcase name)))
          (mode-name (second (assoc :mode options)))
          (initargs (rest (assoc :initargs options))))

      (check-type command-name string)
      (check-type mode-name (or null symbol))
      (check-type initargs list)

      (alexandria:with-unique-names (command universal-argument)
        `(progn
           (check-already-defined-command ',name
                                          #+sbcl (sb-c:source-location)
                                          #-sbcl nil)

            ;; 定义命令函数
            ;; 注意：直接调用此函数（而非通过 call-command）时：
            ;;   - *this-command* 不会被绑定
            ;;   - execute-hook 不会被调用
            (defun ,name ,params
              ,@body)

            ;; 注册命令类
            (register-command-class ',name ',class-name)
            
            ;; 定义命令类（继承 primary-command 和 advice 类）
            (defclass ,class-name (primary-command ,@advice-classes)
              ()
              (:default-initargs
               :source-location #+sbcl (sb-c:source-location) #-sbcl nil
               :name ',name
               ,@initargs))

            ;; 定义 execute 方法：处理参数描述符并调用命令函数
            (defmethod execute (mode (,command ,class-name) ,universal-argument)
              (declare (ignorable ,universal-argument))
              ,(gen-defcommand-body name
                                    universal-argument
                                    arg-descriptors))

            ;; 注册命令到全局命令表
            (register-command (make-instance ',class-name)
                              :mode-name ',mode-name
                              :command-name ,command-name))))))

;;; ============================================================================
;;; Advice 示例
;;; ============================================================================
;;;
;;; Advice 类允许在特定命令执行前后添加自定义逻辑。
;;;
;;; 示例：
;;;   ;; 定义 advice 类
;;;   (defclass my-advice () ())
;;;   
;;;   ;; 为 advice 类定义 execute 方法
;;;   (defmethod execute (mode (command my-advice) argument)
;;;     (format t "Before command: ~A~%" (command-name command))
;;;     (call-next-method)  ; 执行实际命令
;;;     (format t "After command: ~A~%" (command-name command)))
;;;   
;;;   ;; 定义使用 advice 的命令
;;;   (define-command (my-cmd (:advice-classes my-advice)) () ()
;;;     (message "Hello!"))
;;;
;;; #|
;;; (defclass foo-advice () ())
;;; 
;;; (define-command (foo-1 (:advice-classes foo-advice)) (p) ("p")
;;; ...body)
;;; 
;;; (define-command (foo-2 (:advice-classes foo-advice)) (s) ("sInput: ")
;;; ...body)
;;; 
;;; (defmethod execute (mode (command foo-advice) argument)
;;; ;; 只有 :advice-classes 为 foo-advice 的命令会被调用此方法
;;; )
;;; |#
