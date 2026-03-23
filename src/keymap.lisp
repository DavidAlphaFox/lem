;;;; keymap.lisp - Lem 编辑器键映射系统
;;;;
;;;; 本文件实现 Lem 的键绑定系统，负责：
;;;; - 键映射的创建和管理
;;;; - 按键序列到命令的映射
;;;; - 键绑定查找（支持继承）
;;;;
;;;; 核心概念:
;;;; - keymap: 键映射结构，包含按键到命令的映射表
;;;; - key: 按键对象，包含修饰键和符号
;;;; - key sequence: 按键序列，如 (C-x C-f)
;;;;
;;;; 按键表示法:
;;;;   C-  - Control 键
;;;;   M-  - Meta (Alt) 键
;;;;   S-  - Super 键
;;;;   H-  - Hyper 键
;;;;   Shift- - Shift 键
;;;;
;;;; 示例:
;;;;   (define-key *global-keymap* \"C-x C-f\" 'find-file)
;;;;   (define-key *global-keymap* \"M-x\" 'execute-extended-command)
;;;;
;;;; 相关文件:
;;;;   - src/command.lisp: 命令定义和执行
;;;;   - src/input.lisp: 按键读取
;;;;   - src/mode.lisp: 模式相关键映射

(in-package :lem-core)

;;; ============================================================================
;;; 全局变量
;;; ============================================================================

;; 所有已创建键映射的列表
(defvar *keymaps* nil)

;; 特殊键映射（用于内部按键处理）
(defvar *special-keymap* nil)

;;; ============================================================================
;;; 类型定义
;;; ============================================================================

(deftype key-sequence ()
  "按键序列类型：key 对象的列表。"
  '(trivial-types:proper-list key))

(defun keyseq-to-string (key-sequence)
  "将按键序列转换为可读字符串。"
  (check-type key-sequence key-sequence)
  (format nil "~{~A~^ ~}" key-sequence))

;;; ============================================================================
;;; 键映射结构
;;; ============================================================================

(defstruct (keymap (:constructor %make-keymap))
  "键映射结构。
   
   槽位:
     undef-hook     - 未定义键的处理钩子
     parent         - 父键映射（用于继承）
     table          - 按键到命令的哈希表
     function-table - 函数名到命令的哈希表
     name           - 键映射名称（用于调试）"
  undef-hook
  parent
  (table (make-hash-table :test 'eq))
  (function-table (make-hash-table :test 'eq))
  name)

(defmethod print-object ((object keymap) stream)
  "键映射的打印表示。"
  (print-unreadable-object (object stream :identity t :type t)
    (when (keymap-name object)
      (princ (keymap-name object) stream))))

(defun make-keymap (&key undef-hook parent name)
  "创建新的键映射。
   
   参数:
     undef-hook - 未定义键的处理函数
     parent     - 父键映射（查找时会搜索父映射）
     name       - 键映射名称
   
   返回:
     新的 keymap 实例"
  (let ((keymap (%make-keymap
                 :undef-hook undef-hook
                 :parent parent
                 :name name)))
    (push keymap *keymaps*)
    keymap))

(defun prefix-command-p (command)
  "检查命令是否为前缀命令（即嵌套的键映射表）。"
  (hash-table-p command))

;;; ============================================================================
;;; 键绑定定义
;;; ============================================================================

(defun define-key (keymap keyspec command-name)
  "在键映射中定义键绑定。
   
   参数:
     keymap       - 目标键映射
     keyspec      - 按键规范（字符串或符号）
                    字符串格式: \"C-x C-f\", \"M-x\", \"C-M-a\"
                    修饰键前缀: C (Ctrl), M (Meta), S (Super), H (Hyper), Shift
     command-name - 要绑定的命令符号或嵌套键映射
   
   示例:
     ;; 全局绑定
     (define-key *global-keymap* \"C-x C-f\" 'find-file)
     
     ;; 模式特定绑定
     (define-key *lisp-mode-keymap* \"C-c C-c\" 'compile-lisp-file)
     
     ;; 使用符号作为按键
     (define-key *keymap* 'f5 'recompile)"
  (check-type keyspec (or symbol string))
  (check-type command-name (or symbol keymap))
  (typecase keyspec
    (symbol
     (setf (gethash keyspec (keymap-function-table keymap))
           command-name))
    (string
     (let ((keys (parse-keyspec keyspec)))
       (define-key-internal keymap keys command-name))))
  (values))

(defmacro define-keys (keymap &body bindings)
  "批量定义键绑定。
   
   示例:
     (define-keys *global-keymap*
       (\"C-x C-f\" 'find-file)
       (\"C-x C-s\" 'save-file)
       (\"C-x C-c\" 'exit-editor))"
  `(progn ,@(mapcar
             (lambda (binding)
               `(define-key ,keymap
                  ,(first binding)
                  ,(second binding)))
             bindings)))

(defun define-key-internal (keymap keys symbol)
  "内部函数：在键映射表中设置键绑定。
   支持多键序列（如 C-x C-f）的嵌套映射。"
  (loop :with table := (keymap-table keymap)
        :for rest :on (uiop:ensure-list keys)
        :for k := (car rest)
        :do (cond ((null (cdr rest))
                   ;; 最后一个键：设置命令
                   (setf (gethash k table) symbol))
                  (t
                   ;; 不是最后一个键：创建或获取嵌套表
                   (let ((next (gethash k table)))
                     (if (and next (prefix-command-p next))
                         (setf table next)
                         (let ((new-table (make-hash-table :test 'eq)))
                           (setf (gethash k table) new-table)
                           (setf table new-table))))))))

;;; ============================================================================
;;; 键绑定删除
;;; ============================================================================

(defun undefine-key (keymap keyspec)
  "移除键映射中的键绑定。
   
   参数:
     keymap  - 目标键映射
     keyspec - 要移除的按键规范
   
   示例:
     (undefine-key *global-keymap* \"C-k\")"
  (check-type keyspec (or symbol string))
  (typecase keyspec
    (symbol
     (remhash keyspec (keymap-function-table keymap)))
    (string
     (let ((keys (parse-keyspec keyspec)))
       (undefine-key-internal keymap keys))))
  (values))

(defmacro undefine-keys (keymap &body bindings)
  "批量移除键绑定。"
  `(progn ,@(mapcar
             (lambda (binding)
               `(undefine-key ,keymap
                              ,(first binding)))
             bindings)))

(defun undefine-key-internal (keymap keys)
  "内部函数：从键映射表中移除键绑定。"
  (loop :with table := (keymap-table keymap)
        :for rest :on (uiop:ensure-list keys)
        :for k := (car rest)
        :do (cond ((null (cdr rest))
                   (remhash k table))
                  (t
                   (let ((next (gethash k table)))
                     (when (prefix-command-p next)
                       (setf table next)))))))

;;; ============================================================================
;;; 按键规范解析
;;; ============================================================================

(defun parse-keyspec (string)
  "解析按键规范字符串。
   
   输入格式: \"C-x C-f\" 或 \"M-x\"
   
   修饰键前缀:
     C-     - Control
     M-     - Meta (Alt)
     S-     - Super
     H-     - Hyper
     Shift- - Shift
   
   返回: key 对象列表"
  (labels ((fail ()
             (editor-error "parse error: ~A" string))
           (parse (str)
             (loop :with ctrl :and meta :and super :and hyper :and shift
                   :do (cond
                         ((ppcre:scan "^[cmshCMSH]-" str)
                          (ecase (char-downcase (char str 0))
                            ((#\c) (setf ctrl t))
                            ((#\m) (setf meta t))
                            ((#\s) (setf super t))
                            ((#\h) (setf hyper t)))
                          (setf str (subseq str 2)))
                         ((ppcre:scan "^[sS]hift-" str)
                          (setf shift t)
                          (setf str (subseq str 6)))
                         ((string= str "")
                          (fail))
                         ((and (not (insertion-key-sym-p str))
                               (not (named-key-sym-p str)))
                          (fail))
                         (t
                          (return (make-key :ctrl ctrl
                                            :meta meta
                                            :super super
                                            :hyper hyper
                                            :shift shift
                                            :sym (or (named-key-sym-p str)
                                                     str))))))))
    (mapcar #'parse (uiop:split-string string :separator " "))))

;;; ============================================================================
;;; 键映射遍历
;;; ============================================================================

(defun traverse-keymap (keymap fun)
  "遍历键映射中的所有绑定。
   
   参数:
     keymap - 要遍历的键映射
     fun    - 回调函数，接收 (key-sequence command) 两个参数
   
   示例:
     (traverse-keymap *global-keymap*
       (lambda (kseq cmd)
         (format t \"~A -> ~A~%\" kseq cmd)))"
  (labels ((f (table prefix)
             (maphash (lambda (k v)
                        (cond ((prefix-command-p v)
                               ;; 递归遍历嵌套表
                               (f v (cons k prefix)))
                              ((keymap-p v)
                               ;; 递归遍历子键映射
                               (f (keymap-table v) (cons k prefix)))
                              (t
                               ;; 叶节点：调用回调
                               (funcall fun (reverse (cons k prefix)) v))))
                      table)))
    (f (keymap-table keymap) nil)))

;;; ============================================================================
;;; 键绑定查找
;;; ============================================================================

(defgeneric keymap-find-keybind (keymap key cmd)
  (:documentation "在键映射中查找键绑定。
                   
                   参数:
                     keymap - 要搜索的键映射
                     key    - 按键或按键序列
                     cmd    - 默认命令（用于继承链）
                   
                   返回:
                     绑定的命令符号或 nil")
  (:method ((keymap t) key cmd)
    (let ((table (keymap-table keymap)))
      (labels ((f (k)
                 "在当前表中查找按键"
                 (let ((cmd (gethash k table)))
                   (cond ((prefix-command-p cmd)
                          ;; 前缀命令：更新表继续查找
                          (setf table cmd))
                         ((keymap-p cmd)
                          ;; 子键映射：使用其表继续
                          (setf table (keymap-table cmd)))
                         (t
                          ;; 找到命令
                          cmd)))))
        ;; 先搜索父键映射
        (let ((parent (keymap-parent keymap)))
          (when parent
            (setf cmd (keymap-find-keybind parent key cmd))))
        ;; 搜索当前键映射
        (or (etypecase key
              (key
               (f key))
              (list
               (let (cmd)
                 (dolist (k key)
                   (unless (setf cmd (f k))
                     (return)))
                 cmd)))
            ;; 搜索函数表
            (gethash cmd (keymap-function-table keymap))
            ;; 使用未定义钩子
            (keymap-undef-hook keymap)
            cmd)))))

;;; ============================================================================
;;; 按键类型判断
;;; ============================================================================

(defun insertion-key-p (key)
  "检查按键是否为可插入字符。
   
   返回:
     对应的字符，或 nil（如果不是可插入字符）
   
   特殊处理:
     - Return -> #\\Return
     - Tab    -> #\\Tab
     - Space  -> #\\Space"
  (let* ((key (typecase key
                (list (first key))
                (otherwise key)))
         (sym (key-sym key)))
    (cond ((match-key key :sym "Return") #\Return)
          ((match-key key :sym "Tab") #\Tab)
          ((match-key key :sym "Space") #\Space)
          ((and (insertion-key-sym-p sym)
                (match-key key :sym sym))
           (char sym 0)))))

;;; ============================================================================
;;; 活动键映射收集
;;; ============================================================================

(defgeneric compute-keymaps (global-mode)
  (:documentation "根据全局模式计算活动键映射列表。")
  (:method ((mode global-mode)) nil))

(defun all-keymaps ()
  "收集当前所有活动的键映射。
   
   返回键映射列表，按优先级排序（高优先级在前）:
     1. 特殊键映射（如果设置）
     2. 全局模式键映射
     3. 光标位置的模式键映射
     4. 所有活动模式的键映射"
  (let* ((keymaps (compute-keymaps (current-global-mode)))
         (keymaps
           (append keymaps
                   ;; 光标位置的文本模式
                   (alexandria:when-let* ((mode (major-mode-at-point (current-point)))
                                          (keymap (mode-keymap mode)))
                     (list keymap))
                   ;; 所有活动模式
                   (loop :for mode :in (all-active-modes (current-buffer))
                         :when (mode-keymap mode)
                         :collect :it))))
    ;; 添加特殊键映射
    (when *special-keymap*
      (push *special-keymap* keymaps))
    (delete-duplicates (nreverse keymaps))))

;;; ============================================================================
;;; 键绑定查找入口
;;; ============================================================================

(defun lookup-keybind (key &key (keymaps (all-keymaps)))
  "在键映射列表中查找键绑定。
   
   参数:
     key    - 按键或按键序列
     keymap - 要搜索的键映射列表（默认为所有活动键映射）
   
   返回:
     绑定的命令（可能是符号、键映射或 nil）"
  (let (cmd)
    (loop :for keymap :in keymaps
          :do (setf cmd (keymap-find-keybind keymap key cmd)))
    cmd))

(defun find-keybind (key)
  "查找键绑定的命令符号。
   
   与 lookup-keybind 的区别：
   - 只返回符号类型的命令
   - 用于实际命令执行"
  (let ((cmd (lookup-keybind key)))
    (when (symbolp cmd)
      cmd)))

;;; ============================================================================
;;; 命令键绑定收集
;;; ============================================================================

(defun collect-command-keybindings (command keymap)
  "收集命令的所有键绑定。
   
   参数:
     command - 命令符号
     keymap  - 要搜索的键映射
   
   返回:
     按键序列列表"
  (let ((bindings '()))
    (traverse-keymap keymap
                     (lambda (kseq cmd)
                       (when (eq cmd command)
                         (push kseq bindings))))
    (nreverse bindings)))

;;; ============================================================================
;;; 中止键
;;; ============================================================================

;; 中止键绑定（通常是 C-g）
(defvar *abort-key*)

(defun abort-key-p (key)
  "检查按键是否为中止键（如 C-g）。"
  (and (key-p key)
       (eq *abort-key* (lookup-keybind key))))

;;; ============================================================================
;;; 特殊键映射
;;; ============================================================================

(defmacro with-special-keymap ((keymap) &body body)
  "在特殊键映射的上下文中执行代码。
   特殊键映射具有最高优先级。"
  `(let ((*special-keymap* (or ,keymap *special-keymap*)))
     ,@body))
