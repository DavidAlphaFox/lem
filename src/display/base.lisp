;;;; display/base.lisp - Lem 编辑器显示系统基础
;;;;
;;;; 本文件实现 Lem 的显示刷新系统，负责：
;;;; - 屏幕重绘逻辑
;;;; - 窗口渲染协调
;;;; - 浮动窗口和头部窗口的显示管理
;;;;
;;;; 核心概念:
;;;; - redraw-display: 主重绘函数，刷新所有窗口
;;;; - window-redraw: 单个窗口的重绘
;;;; - force 参数: 控制是否强制重绘
;;;;
;;;; 显示层次:
;;;;   1. 头部窗口 (header windows) - 顶部固定区域
;;;;   2. 普通窗口 (regular windows) - 主编辑区域
;;;;   3. 浮动窗口 (floating windows) - 弹出层
;;;;
;;;; 相关文件:
;;;;   - src/interface.lisp: 前端显示接口
;;;;   - src/window/window.lisp: 窗口系统
;;;;   - src/frame.lisp: 帧管理

(in-package :lem-core)

;;; ============================================================================
;;; 显示相关编辑器变量
;;; ============================================================================

;; 换行字符（当行被折行时显示）
(define-editor-variable wrap-line-character #\\
  "行折行时显示的字符。")

;; 折行行的文本属性
(define-editor-variable wrap-line-attribute nil
  "折行行的文本属性（颜色等）。")

;;; ============================================================================
;;; 非活动窗口颜色
;;; ============================================================================

;; 非活动窗口的背景颜色
(defvar *inactive-window-background-color* nil
  "非活动窗口的背景颜色。")

(defun inactive-window-background-color ()
  "获取非活动窗口的背景颜色。"
  *inactive-window-background-color*)

(defun (setf inactive-window-background-color) (color)
  "设置非活动窗口的背景颜色。"
  (setf *inactive-window-background-color* color))

;;; ============================================================================
;;; 重绘泛型函数
;;; ============================================================================

(defgeneric redraw-buffer (implementation buffer window force)
  (:documentation "重绘缓冲区内容到窗口。
                   
                   参数:
                     implementation - 前端实现
                     buffer - 要渲染的缓冲区
                     window - 目标窗口
                     force - 是否强制重绘"))

(defgeneric compute-left-display-area-content (mode buffer point)
  (:documentation "计算窗口左侧显示区域的内容（如行号）。
                   
                   返回: 要显示的内容列表，或 nil")
  (:method (mode buffer point) nil))

(defgeneric compute-wrap-left-area-content (mode left-side-width left-side-characters)
  (:documentation "计算折行时左侧区域的内容。
                   
                   参数:
                     mode - 当前模式
                     left-side-width - 左侧区域宽度
                     left-side-characters - 左侧字符列表")
  (:method (mode left-side-width left-side-characters)
    nil))

;;; ============================================================================
;;; 重绘状态控制
;;; ============================================================================

(defvar *in-redraw-display* nil
  "当屏幕正在被 redraw-display 重绘时为 T。
   用于防止递归调用 redraw-display。")

;;; ============================================================================
;;; 窗口重绘
;;; ============================================================================

(defgeneric window-redraw (window force)
  (:documentation "重绘单个窗口。
                   
                   参数:
                     window - 要重绘的窗口
                     force - 是否强制重绘")
  (:method (window force)
    ;; 重绘窗口的缓冲区内容
    (redraw-buffer (implementation) (window-buffer window) window force)
    ;; 如果有关联的附加窗口，也重绘它
    (when (window-attached-window window)
      (window-redraw (window-attached-window window) force))))

(defun redraw-current-window (window force)
  "重绘当前窗口。
   
   1. 确保光标位置可见 (window-see)
   2. 运行缓冲区显示钩子
   3. 执行窗口重绘"
  (assert (eq window (current-window)))
  (window-see window)
  (run-show-buffer-hooks window)
  (window-redraw window force))

;;; ============================================================================
;;; 全局显示重绘
;;; ============================================================================

(defun redraw-display (&key force)
  "重绘整个显示。
   
   这是 Lem 的主重绘函数，负责刷新所有可见窗口。
   
   参数:
     force - 是否强制重绘所有窗口
   
   重绘顺序:
     1. 头部窗口 (header windows)
     2. 普通窗口 (regular windows)
     3. 浮动窗口 (floating windows)
     4. 更新前端显示
   
   注意:
     - 某些前端（如 DOM 渲染）不需要强制重绘
     - 修改浮动窗口可能需要重绘下层窗口"
  ;; 对于不需要强制重绘的前端，忽略 force 参数
  (when (no-force-needed-p (implementation))
    (setf force nil))
  
  ;; 防止递归调用
  (when *in-redraw-display*
    (log:warn "redraw-display is called recursively")
    (return-from redraw-display))
  
  (let ((*in-redraw-display* t)
        (redraw-after-modifying-floating-window
          (and (not (no-force-needed-p (implementation)))
               (redraw-after-modifying-floating-window (implementation)))))
    
    (labels ((redraw-window-list (force)
               "重绘所有非当前窗口。"
               (dolist (window (window-list))
                 (unless (eq window (current-window))
                   (window-redraw window force)))
               (redraw-current-window (current-window) force))
             
             (redraw-header-windows (force)
               "重绘头部窗口。
                如果有浮动窗口存在，强制重绘头部窗口。"
               (let ((force (or force (not (null (frame-floating-windows (current-frame)))))))
                 (dolist (window (frame-header-windows (current-frame)))
                   (window-redraw window force))))
             
             (redraw-floating-windows ()
               "重绘所有浮动窗口。"
               (dolist (window (frame-floating-windows (current-frame)))
                 (window-redraw window redraw-after-modifying-floating-window)))
             
             (redraw-all-windows ()
               "按顺序重绘所有窗口。"
               (redraw-header-windows force)
               (redraw-window-list
                (if redraw-after-modifying-floating-window
                    ;; 如果浮动窗口被修改，下层窗口需要重绘
                    (or (frame-require-redisplay-windows (current-frame))
                        (frame-modified-floating-windows (current-frame))
                        force)
                    force))
               (redraw-floating-windows)
               ;; 通知前端更新显示
               (lem-if:update-display (implementation))))
      
      (without-interrupts
        ;; 通知前端即将更新显示
        (lem-if:will-update-display (implementation))
        ;; 更新浮动提示窗口
        (update-floating-prompt-window (current-frame))
        ;; 如果头部窗口被修改，调整所有窗口大小
        (when (frame-modified-header-windows (current-frame))
          (adjust-all-window-size))
        ;; 执行重绘
        (redraw-all-windows)
        ;; 通知帧重绘完成
        (notify-frame-redraw-finished (current-frame))))))
