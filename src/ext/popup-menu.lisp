;;;; popup-menu.lisp - Lem 编辑器弹出菜单实现
;;;;
;;;; 本文件实现 Lem 的弹出菜单系统，负责：
;;;; - 菜单项目的显示和选择
;;;; - 键盘导航（上/下/首页/末页）
;;;; - 焦点高亮和选择回调
;;;;
;;;; 核心概念:
;;;; - popup-menu: 弹出菜单类，管理菜单状态
;;;; - focus-overlay: 焦点高亮覆盖层
;;;; - print-spec: 项目打印规范，将对象转换为显示字符串
;;;;
;;;; 菜单操作:
;;;;   popup-menu-down   - 移动到下一项
;;;;   popup-menu-up     - 移动到上一项
;;;;   popup-menu-first  - 移动到第一项
;;;;   popup-menu-last   - 移动到最后一项
;;;;   popup-menu-select - 选择当前项
;;;;   popup-menu-quit   - 关闭菜单
;;;;
;;;; 相关文件:
;;;;   - src/popup.lisp: 弹出菜单公共接口
;;;;   - src/ext/popup-window.lisp: 弹出窗口实现
;;;;   - src/interface.lisp: 前端接口

(defpackage :lem/popup-menu
  (:use :cl :lem)
  (:export :write-header
           :get-focus-item
           :apply-print-spec)
  #+sbcl
  (:lock t))

(in-package :lem/popup-menu)

;;; ============================================================================
;;; Popup-Menu 类定义
;;; ============================================================================

(defclass popup-menu ()
  ((buffer
    :initarg :buffer
    :accessor popup-menu-buffer
    :documentation "菜单内容缓冲区")
   (window
    :initarg :window
    :accessor popup-menu-window
    :documentation "菜单显示窗口")
   (focus-overlay
    :initarg :focus-overlay
    :accessor popup-menu-focus-overlay
    :documentation "当前焦点高亮覆盖层")
   (action-callback
    :initarg :action-callback
    :accessor popup-menu-action-callback
    :documentation "选择项时调用的回调函数")
   (focus-attribute
    :initarg :focus-attribute
    :accessor popup-menu-focus-attribute
    :documentation "焦点行的文本属性"))
  (:documentation "弹出菜单类。
                   管理菜单的显示、导航和选择。"))

;;; ============================================================================
;;; 文本属性定义
;;; ============================================================================

;; 焦点行属性（当前选中项）
(define-attribute popup-menu-attribute
  (t :foreground "white" :background "RoyalBlue")
  (:documentation "菜单焦点行的颜色（白字蓝底）。"))

;; 非焦点行属性
(define-attribute non-focus-popup-menu-attribute
  (:documentation "菜单非焦点行的默认颜色。"))

;;; ============================================================================
;;; 焦点管理
;;; ============================================================================

(defun focus-point (popup-menu)
  "返回菜单缓冲区中的光标位置（焦点点）。"
  (buffer-point (popup-menu-buffer popup-menu)))

(defun make-focus-overlay (point focus-attribute)
  "在指定点创建焦点高亮覆盖层。
   
   参数:
     point - 要高亮的行起点
     focus-attribute - 文本属性
   
   返回:
     覆盖层对象"
  (make-line-overlay point focus-attribute))

(defun update-focus-overlay (popup-menu point)
  "更新焦点高亮位置。
   
   删除旧覆盖层，清除残留覆盖层，在新位置创建覆盖层。
   如果 POINT 在标题行，则不创建覆盖层。
   
   参数:
     popup-menu - 菜单对象
     point - 新的焦点位置"
  (alexandria:when-let ((focus-overlay (popup-menu-focus-overlay popup-menu)))
    (delete-overlay focus-overlay))
  (clear-overlays (popup-menu-buffer popup-menu))
  (unless (header-point-p point)
    (setf (popup-menu-focus-overlay popup-menu)
          (make-focus-overlay point (popup-menu-focus-attribute popup-menu)))))

;;; ============================================================================
;;; 打印规范
;;; ============================================================================

(defgeneric write-header (print-spec point)
  (:documentation "写入菜单标题。
                   
                   参数:
                     print-spec - 打印规范
                     point - 写入位置")
  (:method (print-spec point)
    ;; 默认方法：不写入标题
    ))

(defgeneric apply-print-spec (print-spec point item)
  (:documentation "将菜单项转换为字符串并插入到缓冲区。
                   
                   参数:
                     print-spec - 打印规范（通常是函数）
                     point - 插入位置
                     item - 要显示的菜单项")
  (:method ((print-spec function) point item)
    ;; 默认方法：调用 print-spec 函数获取字符串表示
    (let ((string (funcall print-spec item)))
      (insert-string point string))))

;;; ============================================================================
;;; 菜单项插入
;;; ============================================================================

(defun insert-items (point items print-spec)
  "插入所有菜单项到缓冲区。
   
   参数:
     point - 插入起点
     items - 菜单项列表
     print-spec - 打印规范
   
   每个菜单项会被标记 :item 文本属性，便于后续检索。"
  (with-point ((start point :right-inserting))
    (loop :for (item . continue-p) :on items
          :do (move-point start point)
              (apply-print-spec print-spec point item)
              (line-end point)
              (put-text-property start point :item item)
              (when continue-p
                (insert-character point #\newline)))
    (buffer-start point)))

(defun get-focus-item (popup-menu)
  "获取当前焦点项（用户正在选择的项目）。
   
   参数:
     popup-menu - 菜单对象
   
   返回:
     当前焦点行的菜单项对象，或 nil（如果在标题行）"
  (alexandria:when-let (p (focus-point popup-menu))
    (text-property-at (line-start p) :item)))

;;; ============================================================================
;;; 缓冲区管理
;;; ============================================================================

(defun make-menu-buffer ()
  "创建新的菜单缓冲区。
   
   返回:
     新的临时缓冲区，名称为 '*popup menu*'"
  (make-buffer "*popup menu*" :enable-undo-p nil :temporary t))

(defun buffer-start-line (buffer)
  "获取缓冲区中菜单项的起始行号（跳过标题行）。"
  (buffer-value buffer 'start-line))

(defun (setf buffer-start-line) (line buffer)
  "设置缓冲区中菜单项的起始行号。"
  (setf (buffer-value buffer 'start-line) line))

(defun setup-menu-buffer (buffer items print-spec focus-attribute &optional last-line)
  "设置菜单缓冲区内容。
   
   参数:
     buffer - 目标缓冲区
     items - 菜单项列表
     print-spec - 打印规范
     focus-attribute - 焦点行属性
     last-line - 初始焦点行号（可选，用于保持焦点位置）
   
   返回:
     (values 宽度 焦点覆盖层 高度)"
  (clear-overlays buffer)
  (erase-buffer buffer)
  (setf (variable-value 'line-wrap :buffer buffer) nil)
  (let ((point (buffer-point buffer)))
    ;; 写入标题（如果有）
    (write-header print-spec point)
    (let* ((header-exists (< 0 (length (buffer-text buffer))))
           (start-line (if header-exists
                           (1+ (line-number-at-point point))
                           1)))
      (when (and header-exists
                 (< 0 (length items)))
        (insert-character point #\newline))
      (setf (buffer-start-line buffer) start-line)
      ;; 插入菜单项
      (insert-items point items print-spec)
      (buffer-start point)
      ;; 定位到菜单项起始位置
      (when header-exists
        (move-to-line point start-line))
      ;; 恢复上次的焦点行
      (when last-line (move-to-line point last-line))
      ;; 创建焦点覆盖层
      (let ((focus-overlay (make-focus-overlay point focus-attribute))
            (width (lem/popup-window:compute-buffer-width buffer)))
        (values width
                focus-overlay
                (+ (1- start-line)
                   (length items)))))))

;;; ============================================================================
;;; 默认样式
;;; ============================================================================

;; 默认弹出菜单样式
(defparameter *style* '(:use-border t :offset-y 0)
  "默认弹出菜单样式。
   - :use-border t - 显示边框
   - :offset-y 0 - Y 轴无偏移")

;;; ============================================================================
;;; 前端接口实现
;;; ============================================================================

(defmethod lem-if:display-popup-menu (implementation items
                                      &key action-callback
                                           print-spec
                                           (style *style*)
                                           (max-display-items 20))
  "显示弹出菜单（前端接口实现）。
   
   参数:
     implementation - 前端实现
     items - 菜单项列表
     action-callback - 选择回调函数
     print-spec - 打印规范
     style - 显示样式
     max-display-items - 最大显示项数
   
   返回:
     popup-menu 对象"
  (let ((style (lem/popup-window:ensure-style style))
        (focus-attribute (ensure-attribute 'popup-menu-attribute))
        (non-focus-attribute (ensure-attribute 'non-focus-popup-menu-attribute))
        (buffer (make-menu-buffer)))
    (multiple-value-bind (menu-width focus-overlay height)
        (setup-menu-buffer buffer
                           items
                           print-spec
                           focus-attribute)
      ;; 创建弹出窗口
      (let ((window (lem/popup-window:make-popup-window
                     :source-window (current-window)
                     :buffer buffer
                     :width menu-width
                     :height (min max-display-items height)
                     :style (lem/popup-window:merge-style
                             style
                             :background-color (or (lem/popup-window:style-background-color style)
                                                   (attribute-background
                                                    non-focus-attribute))
                             :cursor-invisible t))))
        (make-instance 'popup-menu
                       :buffer buffer
                       :window window
                       :focus-overlay focus-overlay
                       :action-callback action-callback
                       :focus-attribute focus-attribute)))))

(defmethod lem-if:popup-menu-update (implementation popup-menu items &key print-spec (max-display-items 20) keep-focus)
  "更新弹出菜单内容（前端接口实现）。
   
   参数:
     implementation - 前端实现
     popup-menu - 要更新的菜单
     items - 新的菜单项列表
     print-spec - 打印规范
     max-display-items - 最大显示项数
     keep-focus - 是否保持焦点位置"
  (when popup-menu
    (let ((last-line (line-number-at-point (buffer-point (popup-menu-buffer popup-menu)))))
      (multiple-value-bind (menu-width focus-overlay height)
          (setup-menu-buffer (popup-menu-buffer popup-menu)
                             items
                             print-spec
                             (popup-menu-focus-attribute popup-menu)
                             (if keep-focus last-line))
        (setf (popup-menu-focus-overlay popup-menu) focus-overlay)
        (let ((source-window (current-window)))
          ;; 特殊处理：在提示窗口中显示补全窗口时
          (when (eq source-window
                    (frame-prompt-window (current-frame)))
            ;; 先更新提示窗口位置，避免补全窗口位置偏移
            (lem-core::update-floating-prompt-window (current-frame)))
          ;; 更新弹出窗口大小和位置
          (lem/popup-window:update-popup-window :source-window source-window
                                                 :width menu-width
                                                 :height (min max-display-items height)
                                                 :destination-window (popup-menu-window popup-menu)))))
    ;; 确保焦点不在标题行
    (when (header-point-p (focus-point popup-menu))
      (move-to-line (focus-point popup-menu)
                    (buffer-start-line (popup-menu-buffer popup-menu))))
    (update-focus-overlay popup-menu (focus-point popup-menu))))

(defmethod lem-if:popup-menu-quit (implementation popup-menu)
  "关闭弹出菜单（前端接口实现）。"
  (delete-window (popup-menu-window popup-menu))
  (delete-buffer (popup-menu-buffer popup-menu)))

;;; ============================================================================
;;; 辅助函数
;;; ============================================================================

(defun header-point-p (point)
  "检查点是否在标题行（菜单项之前）。"
  (< (line-number-at-point point)
     (buffer-start-line (point-buffer point))))

(defun move-focus (popup-menu function)
  "移动菜单焦点。
   
   参数:
     popup-menu - 菜单对象
     function - 移动函数，接收点作为参数"
  (alexandria:when-let (point (focus-point popup-menu))
    (funcall function point)
    (line-start point)
    (window-see (popup-menu-window popup-menu))
    (let ((buffer (point-buffer point)))
      ;; 如果移动到标题行，跳到第一个菜单项
      (when (header-point-p point)
        (move-to-line point (buffer-start-line buffer))))
    (update-focus-overlay popup-menu point)))

;;; ============================================================================
;;; 菜单导航命令
;;; ============================================================================

(defmethod lem-if:popup-menu-down (implementation popup-menu)
  "移动到下一项。"
  (move-focus
   popup-menu
   (lambda (point)
     (unless (line-offset point 1)
       (buffer-start point)))))

(defmethod lem-if:popup-menu-up (implementation popup-menu)
  "移动到上一项。"
  (move-focus
   popup-menu
   (lambda (point)
     (unless (line-offset point -1)
       (buffer-end point))
     ;; 如果到达标题行，继续向上到最后一项
     (when (header-point-p point)
       (buffer-end point)))))

(defmethod lem-if:popup-menu-first (implementation popup-menu)
  "移动到第一项。"
  (move-focus
   popup-menu
   (lambda (point)
     (buffer-start point))))

(defmethod lem-if:popup-menu-last (implementation popup-menu)
  "移动到最后一项。"
  (move-focus
   popup-menu
   (lambda (point)
     (buffer-end point))))

(defmethod lem-if:popup-menu-select (implementation popup-menu)
  "选择当前项并调用回调函数。"
  (alexandria:when-let ((f (popup-menu-action-callback popup-menu))
                        (item (get-focus-item popup-menu)))
    (funcall f item)))
