;;;; modeline.lisp - Lem 编辑器模式行系统
;;;;
;;;; 本文件实现 Lem 的模式行（状态栏）系统，负责：
;;;; - 模式行的内容定义和渲染
;;;; - 显示缓冲区信息（名称、位置、模式等）
;;;; - 活动和非活动窗口的不同显示样式
;;;;
;;;; 模式行元素:
;;;;   modeline-write-info   - 写入状态（只读/已修改）
;;;;   modeline-name         - 缓冲区名称
;;;;   modeline-major-mode   - 主模式名称
;;;;   modeline-minor-modes  - 次模式列表
;;;;   modeline-position     - 光标位置（行:列）
;;;;   modeline-posline      - 滚动位置（Top/Bot/All/百分比）
;;;;
;;;; 自定义模式行:
;;;;   - 修改 modeline-format 变量
;;;;   - 使用 modeline-add-status-list 添加临时状态
;;;;
;;;; 相关文件:
;;;;   - src/window/window.lisp: 窗口系统
;;;;   - src/attribute.lisp: 文本属性定义

(in-package :lem-core)

;;; ============================================================================
;;; 模式行格式定义
;;; ============================================================================

;; 默认模式行格式
;; 元素可以是：字符串、函数名、或 (元素 属性 对齐方式) 列表
(define-editor-variable modeline-format '("  "
                                          modeline-write-info
                                          modeline-name
                                          (modeline-posline nil :right)
                                          (modeline-position nil :right)
                                          (modeline-minor-modes nil :right)
                                          (modeline-major-mode nil :right))
  "模式行格式规范。
   
   每个元素可以是：
   - 字符串：直接显示
   - 符号：调用对应的函数，显示返回值
   - 列表：(元素 属性 对齐方式)
     - 属性：文本属性名或 nil
     - 对齐方式：:left 或 :right")

;;; ============================================================================
;;; 模式行文本属性
;;; ============================================================================

;; 活动窗口的缓冲区名称属性
(define-attribute modeline-name-attribute
  (t :foreground "orange")
  (:documentation "活动窗口模式行中缓冲区名称的颜色。"))

;; 非活动窗口的缓冲区名称属性
(define-attribute inactive-modeline-name-attribute
  (t :foreground "#996300")
  (:documentation "非活动窗口模式行中缓冲区名称的颜色。"))

;; 活动窗口的主模式属性
(define-attribute modeline-major-mode-attribute
  (t :foreground "#85b8ff")
  (:documentation "活动窗口模式行中主模式名称的颜色。"))

;; 非活动窗口的主模式属性
(define-attribute inactive-modeline-major-mode-attribute
  (t :foreground "#325587")
  (:documentation "非活动窗口模式行中主模式名称的颜色。"))

;; 活动窗口的次模式属性
(define-attribute modeline-minor-modes-attribute
  (t :foreground "#FFFFFF")
  (:documentation "活动窗口模式行中次模式列表的颜色。"))

;; 非活动窗口的次模式属性
(define-attribute inactive-modeline-minor-modes-attribute
  (t :foreground "#808080")
  (:documentation "非活动窗口模式行中次模式列表的颜色。"))

;; 活动窗口的位置属性
(define-attribute modeline-position-attribute
  (t :foreground "#FAFAFA" :background "#202020")
  (:documentation "活动窗口模式行中光标位置的颜色。"))

;; 非活动窗口的位置属性
(define-attribute inactive-modeline-position-attribute
  (t :foreground "#888888" :background "#202020")
  (:documentation "非活动窗口模式行中光标位置的颜色。"))

;; 活动窗口的滚动位置属性
(define-attribute modeline-posline-attribute
  (t :foreground "black" :background "#A0A0A0")
  (:documentation "活动窗口模式行中滚动位置的颜色。"))

;; 非活动窗口的滚动位置属性
(define-attribute inactive-modeline-posline-attribute
  (t :foreground "black" :background "#505050")
  (:documentation "非活动窗口模式行中滚动位置的颜色。"))

;;; ============================================================================
;;; 状态列表管理
;;; ============================================================================

;; 全局状态列表
(defvar *modeline-status-list* nil
  "全局模式行状态列表，用于显示临时信息。")

(defun modeline-add-status-list (x &optional (buffer nil bufferp))
  "向模式行状态列表添加元素。
   
   参数:
     x - 要添加的状态元素
     buffer - 目标缓冲区（可选，nil 表示全局）
   
   示例:
     ;; 添加全局状态
     (modeline-add-status-list '(\" [RECORDING]\")
     
     ;; 添加缓冲区局部状态
     (modeline-add-status-list '(\" [READ-ONLY]\") buffer)"
  (if bufferp
      (pushnew x (buffer-value buffer 'modeline-status-list))
      (pushnew x *modeline-status-list*))
  (values))

(defun modeline-remove-status-list (x &optional (buffer nil bufferp))
  "从模式行状态列表移除元素。
   
   参数:
     x - 要移除的状态元素
     buffer - 目标缓冲区（可选）"
  (if bufferp
      (setf (buffer-value buffer 'modeline-status-list)
            (remove x (buffer-value buffer 'modeline-status-list)))
      (setf *modeline-status-list*
            (remove x *modeline-status-list*))))

(defun modeline-clear-status-list (&optional (buffer nil bufferp))
  "清空模式行状态列表。
   
   参数:
     buffer - 目标缓冲区（可选）"
  (if bufferp
      (setf (buffer-value buffer 'modeline-status-list) '())
      (setf *modeline-status-list* '())))

;;; ============================================================================
;;; 模式行元素函数
;;; ============================================================================

(defun modeline-write-info (window)
  "返回缓冲区写入状态图标。
   
   返回:
     - 锁图标（只读缓冲区）
     - 圆点图标（已修改缓冲区）
     - 空格（未修改缓冲区）"
  (let ((buffer (window-buffer window)))
    (cond ((buffer-read-only-p buffer)
           (format nil " ~a" (icon-string "lock")))
          ((buffer-modified-p buffer)
           (format nil " ~a" (icon-string "bullet-point")))
          (t
           "   "))))

(defun modeline-name (window)
  "返回缓冲区名称。
   
   返回:
     (values 名称 属性)
     - 名称：缓冲区名称字符串
     - 属性：活动或非活动名称属性"
  (values (buffer-name (window-buffer window))
          (if (eq (current-window) window)
              'modeline-name-attribute
              'inactive-modeline-name-attribute)))

(defun modeline-major-mode (window)
  "返回主模式名称。
   
   返回:
     (values 名称 属性)
     - 名称：主模式名称字符串
     - 属性：活动或非活动主模式属性"
  (values (concatenate 'string
                       (mode-name (buffer-major-mode (window-buffer window)))
                       " ")
          (if (eq (current-window) window)
              'modeline-major-mode-attribute
              'inactive-modeline-major-mode-attribute)))

(defun modeline-minor-modes (window)
  "返回次模式列表字符串。
   
   返回:
     (values 字符串 属性)
     - 字符串：所有可见次模式的名称
     - 属性：活动或非活动次模式属性"
  (values (with-output-to-string (out)
            (dolist (mode (append (buffer-minor-modes (window-buffer window))
                                  (active-global-minor-modes)))
              (when (and (mode-name mode)
                         (not (mode-hide-from-modeline mode)))
                (princ (mode-name mode) out)
                (princ " " out))))
          (if (eq (current-window) window)
              'modeline-minor-modes-attribute
              'inactive-modeline-minor-modes-attribute)))

(defun modeline-position (window)
  "返回光标位置（行:列）。
   
   返回:
     (values 位置字符串 属性)
     - 位置字符串：格式为 \" 行:列 \"
     - 属性：活动或非活动位置属性"
  (values (format nil
                  " ~D:~D "
                  (line-number-at-point (window-point window))
                  (point-column (window-point window)))
          (if (eq window (current-window))
              'modeline-position-attribute
              'inactive-modeline-position-attribute)))

(defun modeline-posline (window)
  "返回滚动位置指示器。
   
   返回:
     (values 位置字符串 属性)
     - 位置字符串：
       - \"  All  \" - 所有内容可见
       - \"  Top  \" - 在文件顶部
       - \"  Bot  \" - 在文件底部
       - \"  XX%  \" - 当前位置百分比
     - 属性：活动或非活动滚动位置属性"
  (values (cond
            ((<= (buffer-nlines (window-buffer window))
                 (window-height window))
             "  All  ")
            ((first-line-p (window-view-point window))
             "  Top  ")
            ((null (line-offset (copy-point (window-view-point window)
                                            :temporary)
                                (window-height window)))
             "  Bot  ")
            (t
             (format nil "  ~2d%  "
                     (floor
                      (* 100
                         (float (/ (line-number-at-point (window-view-point window))
                                   (buffer-nlines (window-buffer window)))))))))
          (if (eq (current-window) window)
              'modeline-posline-attribute
              'inactive-modeline-posline-attribute)))

;;; ============================================================================
;;; 模式行元素转换
;;; ============================================================================

(defgeneric convert-modeline-element (element window)
  (:documentation "将模式行元素转换为可显示的字符串。"))

(defmethod convert-modeline-element ((element t) window)
  "默认方法：将任意元素转换为字符串。"
  (princ-to-string element))

(defmethod convert-modeline-element ((element function) window)
  "函数元素：调用函数获取值。"
  (multiple-value-bind (name attribute alignment)
      (funcall element window)
    (values name attribute alignment)))

(defmethod convert-modeline-element ((element symbol) window)
  "符号元素：调用符号绑定的函数。"
  (convert-modeline-element (symbol-function element) window))

(defun modeline-apply-1 (window print-fn default-attribute items)
  "应用模式行元素列表。
   
   参数:
     window - 目标窗口
     print-fn - 打印函数，接收 (字符串 属性 对齐方式)
     default-attribute - 默认文本属性
     items - 模式行元素列表"
  (dolist (item items)
    (multiple-value-bind (name attribute alignment)
        (if (consp item)
            (values (first item)
                    (if (second item)
                        (merge-attribute (ensure-attribute (second item) nil)
                                         (ensure-attribute default-attribute nil))
                        default-attribute)
                    (or (third item) :left))
            (values item
                    default-attribute
                    :left))
      (let (attribute-1 alignment-1)
        (setf (values name attribute-1 alignment-1)
              (convert-modeline-element name window))
        (when attribute-1
          (setf attribute
                (merge-attribute (ensure-attribute attribute nil)
                                 (ensure-attribute attribute-1 nil))))
        (when alignment-1 (setf alignment alignment-1)))
      (funcall print-fn
               (princ-to-string name)
               attribute
               alignment))))

(defun modeline-apply (window print-fn default-attribute)
  "应用完整的模式行格式。
   
   参数:
     window - 目标窗口
     print-fn - 打印函数
     default-attribute - 默认文本属性
   
   处理顺序:
     1. window-modeline-format 或 buffer 的 modeline-format
     2. 缓冲区局部状态列表
     3. 全局状态列表"
  (modeline-apply-1 window
                    print-fn
                    default-attribute
                    (or (window-modeline-format window)
                        (variable-value 'modeline-format :default (window-buffer window))))
  ;; 添加缓冲区局部状态
  (alexandria:when-let ((items (buffer-value (window-buffer window) 'modeline-status-list)))
    (modeline-apply-1 window print-fn default-attribute items))
  ;; 添加全局状态
  (alexandria:when-let ((items *modeline-status-list*))
    (modeline-apply-1 window print-fn default-attribute items)))
