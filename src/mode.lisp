;;;; mode.lisp - Lem 编辑器模式系统
;;;;
;;;; 本文件实现 Lem 的模式系统，包括：
;;;; - 主模式 (major-mode): 每个缓冲区一个，定义语言特性
;;;; - 次模式 (minor-mode): 可多个，提供附加功能
;;;; - 全局次模式 (global-minor-mode): 全局激活的次模式
;;;; - 全局模式 (global-mode): 独占式全局模式
;;;;
;;;; 模式继承层次:
;;;;   mode
;;;;   ├── major-mode ─── language-mode ─── lisp-mode, python-mode, ...
;;;;   ├── minor-mode
;;;;   │   └── global-minor-mode
;;;;   └── global-mode
;;;;
;;;; 相关宏:
;;;;   - define-major-mode: 定义主模式
;;;;   - define-minor-mode: 定义次模式
;;;;   - define-global-mode: 定义全局模式
;;;;
;;;; 相关文件:
;;;;   - src/ext/language-mode.lisp: 语言模式基类
;;;;   - extensions/*-mode/: 具体语言模式实现

(in-package :lem-core)

;;; ============================================================================
;;; 全局状态变量
;;; ============================================================================

;; 当前激活的全局次模式列表
(defvar *active-global-minor-modes* '())

;; 当前全局模式（如 vi-mode）
(defvar *current-global-mode* nil)

;;; ============================================================================
;;; 模式注册表
;;; ============================================================================

;; 所有已注册模式对象的列表
(defvar *mode-objects* '())

(defgeneric mode-identifier-name (mode)
  (:documentation "返回模式的标识符名称。"))

(defun get-mode-object (mode-name)
  "根据模式名称获取模式对象。
   模式对象存储在模式名称符号的 'mode-object 属性中。"
  (get mode-name 'mode-object))

(defun register-mode (name object)
  "注册模式对象。
   NAME: 模式名称符号
   OBJECT: 模式实例
   
   将模式添加到 *mode-objects* 列表，并设置符号属性。"
  (setf *mode-objects*
        (cons object
              (remove name
                      *mode-objects*
                      :key #'mode-identifier-name
                      :test #'eq)))
  (setf (get name 'mode-object) object))

(defun collect-modes (test-function)
  "收集满足条件的模式对象，按名称排序。"
  (sort (remove-if-not test-function *mode-objects*)
        #'string<
        :key #'mode-identifier-name))

;;; ============================================================================
;;; 模式类定义
;;; ============================================================================

(defclass mode ()
  ((name :initarg :name :reader mode-name
         :documentation "模式显示名称")
   (description :initarg :description :reader mode-description
                :documentation "模式描述")
   (keymap :initarg :keymap :reader mode-keymap :writer set-mode-keymap
           :documentation "模式键映射")
   (commands :initform '() :accessor mode-commands
             :documentation "模式关联的命令列表")
   (hide-from-modeline :initarg :hide-from-modeline :reader mode-hide-from-modeline
                       :documentation "是否在模式行隐藏"))
  (:documentation "所有模式的基类。"))

(defclass major-mode (mode)
  ((syntax-table :initarg :syntax-table :reader mode-syntax-table
                 :documentation "语法定义表")
   (hook-variable :initarg :hook-variable :reader mode-hook-variable
                  :documentation "模式钩子变量"))
  (:documentation "主模式基类。
                   每个缓冲区只有一个主模式。
                   主模式定义语言的语法高亮、缩进规则等。
                   
                   示例: lisp-mode, python-mode, javascript-mode"))

(defclass minor-mode (mode)
  ((enable-hook :initarg :enable-hook :reader mode-enable-hook
                :documentation "启用时调用的钩子")
   (disable-hook :initarg :disable-hook :reader mode-disable-hook
                 :documentation "禁用时调用的钩子"))
  (:documentation "次模式基类。
                   每个缓冲区可有多个次模式。
                   次模式提供附加功能，如自动补全、括号匹配等。
                   
                   示例: lsp-mode, paredit-mode, auto-fill-mode"))

(defclass global-minor-mode (minor-mode) ()
  (:documentation "全局次模式。
                   激活后对所有缓冲区生效。
                   
                   示例: vi-mode"))

(defclass global-mode (mode)
  ((enable-hook :initarg :enable-hook :reader mode-enable-hook
                :documentation "启用时调用的钩子")
   (disable-hook :initarg :disable-hook :reader mode-disable-hook
                 :documentation "禁用时调用的钩子"))
  (:documentation "独占式全局模式。
                   同一时间只有一个全局模式可以激活。
                   
                   示例: vi-mode 的普通模式"))

;;; ============================================================================
;;; 模式对象访问方法
;;; ============================================================================

(defmethod mode-identifier-name ((mode mode))
  "默认实现：使用类名作为标识符名称。"
  (type-of mode))

(defun ensure-mode-object (mode)
  "确保返回模式对象。
   如果 MODE 是符号，获取对应的模式对象；
   如果已经是模式对象，直接返回。"
  (etypecase mode
    (symbol (get-mode-object mode))
    (mode mode)))

(defun major-mode-p (mode)
  "检查是否为主模式。"
  (typep (ensure-mode-object mode) 'major-mode))

(defun minor-mode-p (mode)
  "检查是否为次模式。"
  (typep (ensure-mode-object mode) 'minor-mode))

(defun global-minor-mode-p (mode)
  "检查是否为全局次模式。"
  (typep (ensure-mode-object mode) 'global-minor-mode))

;;; ----------------------------------------------------------------------------
;;; 符号访问方法（允许用符号代替模式对象）
;;; ----------------------------------------------------------------------------

(defmethod mode-name ((mode symbol))
  "符号版本的模式名称访问。"
  (assert (not (null mode)))
  (mode-name (get-mode-object mode)))

(defmethod mode-description ((mode symbol))
  (assert (not (null mode)))
  (mode-description (get-mode-object mode)))

(defmethod mode-keymap ((mode symbol))
  (assert (not (null mode)))
  (mode-keymap (get-mode-object mode)))

(defmethod mode-syntax-table ((mode symbol))
  (assert (not (null mode)))
  (mode-syntax-table (get-mode-object mode)))

(defmethod mode-enable-hook ((mode symbol))
  (assert (not (null mode)))
  (mode-enable-hook (get-mode-object mode)))

(defmethod mode-disable-hook ((mode symbol))
  (assert (not (null mode)))
  (mode-disable-hook (get-mode-object mode)))

(defmethod mode-hook-variable ((mode symbol))
  (assert (not (null mode)))
  (mode-hook-variable (get-mode-object mode)))

(defmethod mode-hide-from-modeline ((mode symbol))
  (assert (not (null mode)))
  (mode-hide-from-modeline (get-mode-object mode)))

;;; ============================================================================
;;; 模式查询函数
;;; ============================================================================

(defun major-modes ()
  "返回所有已注册主模式的名称列表。"
  (mapcar #'mode-identifier-name (collect-modes #'major-mode-p)))

(defun minor-modes ()
  "返回所有已注册次模式的名称列表。"
  (mapcar #'mode-identifier-name (collect-modes #'minor-mode-p)))

(defun find-mode (mode-name)
  "根据名称查找主模式对象。"
  (find mode-name (major-modes) :key #'mode-name :test #'string-equal))

(defun active-global-minor-modes ()
  "返回当前激活的全局次模式列表。"
  *active-global-minor-modes*)

(defun current-global-mode ()
  "返回当前全局模式。"
  *current-global-mode*)

(defun all-active-modes (buffer)
  "返回缓冲区中所有激活的模式对象列表。
   
   顺序（优先级从低到高）:
   1. 缓冲区的次模式
   2. 缓冲区的主模式
   3. 全局次模式
   4. 全局模式"
  (mapcar #'ensure-mode-object
          (append (buffer-minor-modes buffer)
                  (list (buffer-major-mode buffer))
                  (active-global-minor-modes)
                  (list (current-global-mode)))))

(defun mode-active-p (buffer mode)
  "检查模式是否在缓冲区中激活。"
  (not (null (find mode (all-active-modes buffer) :key #'mode-identifier-name))))

;;; ============================================================================
;;; 模式切换
;;; ============================================================================

(defun change-buffer-mode (buffer mode &rest args)
  "切换缓冲区的主模式。
   
   BUFFER: 目标缓冲区
   MODE: 新模式命令
   ARGS: 传递给模式命令的参数"
  (save-excursion
    (setf (current-buffer) buffer)
    (apply mode args))
  buffer)

(defun make-mode-command-class-name (mode-name)
  "生成模式命令类名称。"
  (make-symbol (format nil "~A~A" mode-name '#:-command)))

(defun associate-command-with-mode (mode-name command-name)
  "将命令与模式关联。"
  (let ((mode (get-mode-object mode-name)))
    (unless (find command-name (mode-commands mode) :test #'command-equal)
      (alexandria:nconcf (mode-commands mode) (list command-name))))
  (values))

;;; ============================================================================
;;; 主模式定义宏
;;; ============================================================================

(defmacro define-major-mode (major-mode
                             parent-mode
                             (&key name
                                   description
                                   keymap
                                   (syntax-table '(fundamental-syntax-table))
                                   mode-hook
                                   formatter)
                             &body body)
  "定义主模式。
   
   参数:
     MAJOR-MODE: 模式命令名称（符号）
     PARENT-MODE: 父模式（用于继承键映射等）
     NAME: 显示名称（字符串）
     DESCRIPTION: 模式描述
     KEYMAP: 键映射变量名
     SYNTAX-TABLE: 语法表表达式
     MODE-HOOK: 模式钩子变量名
     FORMATTER: 格式化函数
   
   模式体:
     在模式切换时执行的代码，用于设置缓冲区变量等。
   
   示例:
     (define-major-mode lisp-mode language-mode
         (:name \"Lisp\"
          :keymap *lisp-mode-keymap*
          :syntax-table *lisp-syntax-table*
          :mode-hook *lisp-mode-hook*)
       (setf (variable-value 'line-comment) \";\")
       (setf (variable-value 'tab-width) 2))"
  (let ((command-class-name (make-mode-command-class-name major-mode)))
    `(progn
       ,@(when mode-hook
           `((defvar ,mode-hook '())))
       ,@(when keymap
           `((defvar ,keymap (make-keymap :name ',keymap
                                          :parent ,(when parent-mode
                                                     `(mode-keymap ',parent-mode))))))
       (define-command (,major-mode (:class ,command-class-name)) () ()
         (clear-editor-local-variables (current-buffer))
         ,(when parent-mode `(,parent-mode))
         (setf (buffer-major-mode (current-buffer)) ',major-mode)
         (setf (buffer-syntax-table (current-buffer)) (mode-syntax-table ',major-mode))
         ,@body
         ,(when mode-hook
            `(run-hooks ,mode-hook)))
       (defclass ,major-mode (,(or parent-mode 'major-mode))
         ()
         (:default-initargs
          :name ,name
          :description ,description
          :keymap ,keymap
          :syntax-table ,syntax-table
          :hook-variable ',mode-hook))
       (register-mode ',major-mode (make-instance ',major-mode))
       (when ,formatter (register-formatter ,major-mode ,formatter)))))

;;; ============================================================================
;;; 次模式操作
;;; ============================================================================

(defun enable-minor-mode (minor-mode)
  "启用次模式。
   如果是全局次模式，添加到全局列表；
   否则添加到当前缓冲区的次模式列表。"
  (if (global-minor-mode-p minor-mode)
      (pushnew minor-mode *active-global-minor-modes*)
      (pushnew minor-mode (buffer-minor-modes (current-buffer))))
  (when (mode-enable-hook minor-mode)
    (funcall (mode-enable-hook minor-mode))))

(defun disable-minor-mode (minor-mode)
  "禁用次模式。
   从全局列表或缓冲区次模式列表中移除。"
  (if (global-minor-mode-p minor-mode)
      (setf *active-global-minor-modes*
            (delete minor-mode *active-global-minor-modes*))
      (setf (buffer-minor-modes (current-buffer))
            (delete minor-mode (buffer-minor-modes (current-buffer)))))
  (when (mode-disable-hook minor-mode)
    (funcall (mode-disable-hook minor-mode))))

(defun toggle-minor-mode (minor-mode)
  "切换次模式的激活状态。"
  (if (mode-active-p (current-buffer) minor-mode)
      (disable-minor-mode minor-mode)
      (enable-minor-mode minor-mode)))

(defmacro define-minor-mode (minor-mode
                             (&key name
                                   description
                                   (keymap nil keymapp)
                                   global
                                   enable-hook
                                   disable-hook
                                   hide-from-modeline)
                             &body body)
  "定义次模式。
   
   参数:
     MINOR-MODE: 模式命令名称（符号）
     NAME: 显示名称
     DESCRIPTION: 模式描述
     KEYMAP: 键映射变量名（可选）
     GLOBAL: 是否为全局次模式
     ENABLE-HOOK: 启用钩子
     DISABLE-HOOK: 禁用钩子
     HIDE-FROM-MODELINE: 是否在模式行隐藏
   
   模式体:
     在模式切换后执行的代码。
   
   示例:
     (define-minor-mode auto-fill-mode
         (:name \"Auto Fill\"
          :description \"自动换行\")
       (message \"Auto fill mode ~A\" 
                (if (mode-active-p (current-buffer) 'auto-fill-mode)
                    \"enabled\"
                    \"disabled\")))"
  (let ((command-class-name (make-mode-command-class-name minor-mode)))
    `(progn
       ,@(when keymapp
           `((defvar ,keymap (make-keymap :name ',keymap))))
       (define-command (,minor-mode (:class ,command-class-name)) (&optional (arg nil arg-p)) (:universal)
         (cond ((not arg-p)
                (toggle-minor-mode ',minor-mode))
               ((eq arg t)
                (enable-minor-mode ',minor-mode))
               ((eq arg nil)
                (disable-minor-mode ',minor-mode))
               ((integerp arg)
                (toggle-minor-mode ',minor-mode))
               (t
                (error "Invalid arg: ~S" arg)))
         ,@body)
       (defclass ,minor-mode (,(if global 'global-minor-mode 'minor-mode))
         ()
         (:default-initargs
          :name ,name
          :description ,description
          :keymap ,keymap
          :enable-hook ,enable-hook
          :disable-hook ,disable-hook
          :hide-from-modeline ,hide-from-modeline))
       (register-mode ',minor-mode (make-instance ',minor-mode)))))

;;; ============================================================================
;;; 全局模式
;;; ============================================================================

(defun change-global-mode-keymap (mode keymap)
  "更改全局模式的键映射。"
  (set-mode-keymap keymap (ensure-mode-object mode)))

(defun change-global-mode (mode)
  "切换全局模式。
   先禁用当前全局模式，再启用新模式。"
  (flet ((call (fun)
           (unless (null fun)
             (alexandria:when-let ((fun (alexandria:ensure-function fun)))
               (funcall fun)))))
    (let ((global-mode (ensure-mode-object mode)))
      (check-type global-mode global-mode)
      (when *current-global-mode*
        (call (mode-disable-hook *current-global-mode*)))
      (setf *current-global-mode* global-mode)
      (call (mode-enable-hook global-mode)))))

(defmacro define-global-mode (mode (&optional parent) (&key name keymap enable-hook disable-hook))
  "定义全局模式。
   
   参数:
     MODE: 模式命令名称
     PARENT: 父模式（可选）
     NAME: 显示名称
     KEYMAP: 键映射变量名
     ENABLE-HOOK: 启用钩子
     DISABLE-HOOK: 禁用钩子
   
   全局模式是独占的，同一时间只能有一个激活。"
  (check-type parent symbol)
  (alexandria:with-gensyms (global-mode parent-mode)
    (let ((command-class-name (make-mode-command-class-name mode)))
      `(progn
         ,@(when keymap
             `((defvar ,keymap
                 (make-keymap :name ',keymap
                              :parent (alexandria:when-let ((,parent-mode
                                                             ,(when parent
                                                                `(get-mode-object ',parent))))
                                        (mode-keymap ,parent-mode))))))
         (defclass ,mode (global-mode) ()
           (:default-initargs
            :name ,name
            :keymap ,keymap
            :enable-hook ,enable-hook
            :disable-hook ,disable-hook))
         (let ((,global-mode (make-instance ',mode)))
           (register-mode ',mode ,global-mode)
           (unless *current-global-mode*
             (setf *current-global-mode* ,global-mode)))
         (define-command (,mode (:class ,command-class-name)) () ()
           (change-global-mode ',mode))))))

;;; ============================================================================
;;; 模式类缓存
;;; ============================================================================

(defun all-active-mode-classes (buffer)
  "返回缓冲区所有激活模式的类对象列表。"
  (mapcar #'class-of (all-active-modes buffer)))

(defconstant +active-modes-class-name+ '%active-modes-class
  "活动模式类名前缀。")

(defun buffer-mode-class-name (buffer)
  "生成缓冲区特定的模式类名称。"
  (alexandria:symbolicate +active-modes-class-name+ '- (buffer-name buffer)))

(defun buffer-active-modes-class-cache (buffer)
  "获取缓冲区的模式类缓存。"
  (buffer-value buffer 'mode-class-cache))

(defun (setf buffer-active-modes-class-cache) (value buffer)
  "设置缓冲区的模式类缓存。"
  (setf (buffer-value buffer 'mode-class-cache) value))

(defun get-active-modes-class-instance (buffer)
  "获取缓冲区活动模式的组合类实例。
   
   使用 CLOS 多重继承动态创建组合所有活动模式的类。
   结果被缓存以提高性能。"
  (let ((mode-classes (all-active-mode-classes buffer)))
    (cond ((or (null (buffer-active-modes-class-cache buffer))
               (not (equal (car (buffer-active-modes-class-cache buffer))
                           (mapcar #'class-name mode-classes))))
           (let ((instance
                   (make-instance
                    (c2mop:ensure-class (buffer-mode-class-name buffer)
                                        :direct-superclasses mode-classes))))
             (setf (buffer-active-modes-class-cache buffer)
                   (cons (mapcar #'class-name mode-classes)
                         instance))
             instance))
          (t
           (cdr (buffer-active-modes-class-cache buffer))))))

(defun get-syntax-table-by-mode-name (mode-name)
  "根据模式名称获取语法表。"
  (alexandria:when-let* ((mode (find-mode mode-name))
                         (syntax-table (mode-syntax-table mode)))
    syntax-table))

;;; ============================================================================
;;; 区域模式
;;; ============================================================================

(defun clear-region-major-mode (start end)
  "清除区域内文本的模式属性。"
  (remove-text-property start end :mode))

(defun set-region-major-mode (start end mode)
  "设置区域内文本的模式属性。"
  (put-text-property start end :mode mode))

(defun major-mode-at-point (point)
  "获取点位置的模式属性。"
  (text-property-at point :mode))

(defun current-major-mode-at-point (point)
  "获取点位置的当前模式。
   如果文本没有模式属性，返回缓冲区的主模式。"
  (or (major-mode-at-point point)
      (buffer-major-mode (point-buffer point))))

(defun call-with-major-mode (buffer mode function)
  "在指定模式下执行函数，执行后恢复原模式。"
  (let ((previous-mode (buffer-major-mode buffer)))
    (cond ((eq previous-mode mode)
           (funcall function))
          (t
           (change-buffer-mode buffer mode)
           (unwind-protect (funcall function)
             (change-buffer-mode buffer previous-mode))))))

(defmacro with-major-mode (mode &body body)
  "在指定模式下执行代码体。
   
   示例:
     (with-major-mode 'lisp-mode
       (format t \"Current mode: ~A\" (buffer-major-mode (current-buffer))))"
  `(call-with-major-mode (current-buffer) ,mode (lambda () ,@body)))

(defgeneric paste-using-mode (mode text)
  (:documentation "使用指定模式粘贴文本。"))
