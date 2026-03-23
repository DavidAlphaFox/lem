;;;; popup-window.lisp - Lem 编辑器弹出窗口系统
;;;;
;;;; 本文件实现 Lem 的浮动弹出窗口系统，负责：
;;;; - 弹出窗口的创建和定位
;;;; - 多种位置模式（gravity）支持
;;;; - 窗口边框和样式管理
;;;;
;;;; 核心概念:
;;;; - popup-window: 浮动窗口类，继承自 floating-window
;;;; - gravity: 位置计算策略，决定窗口显示位置
;;;; - style: 窗口样式（边框、颜色、光标等）
;;;;
;;;; 位置模式 (gravity):
;;;;   :center                          - 屏幕中央
;;;;   :top-display                     - 显示区域顶部
;;;;   :bottom-display                  - 显示区域底部
;;;;   :top                             - 源窗口上方
;;;;   :topright                        - 源窗口右上角
;;;;   :cursor                          - 光标位置（默认）
;;;;   :follow-cursor                   - 跟随光标移动
;;;;   :mouse-cursor                    - 鼠标位置
;;;;   :vertically-adjacent-window      - 垂直相邻窗口
;;;;   :vertically-adjacent-window-dynamic - 动态垂直相邻
;;;;   :horizontally-adjacent-window    - 水平相邻窗口
;;;;   :horizontally-above-window       - 水平上方窗口
;;;;
;;;; 样式选项 (style):
;;;;   :gravity         - 位置模式
;;;;   :use-border      - 是否显示边框
;;;;   :background-color - 背景颜色
;;;;   :offset-x        - X 轴偏移
;;;;   :offset-y        - Y 轴偏移
;;;;   :cursor-invisible - 是否隐藏光标
;;;;   :shape           - 边框形状
;;;;
;;;; 相关文件:
;;;;   - src/popup.lisp: 弹出窗口公共接口
;;;;   - src/ext/popup-menu.lisp: 弹出菜单实现
;;;;   - src/window/floating-window.lisp: 浮动窗口基类

;;;; popup-window.lisp - Lem 编辑器弹出窗口系统
;;;;
;;;; 本文件实现 Lem 的弹出窗口系统，负责：
;;;; - 弹出窗口的位置计算和创建
;;;; - 多种位置模式（gravity）支持
;;;; - 窗口样式配置
;;;;
;;;; 核心概念:
;;;; - popup-window: 弹出窗口类，继承自 floating-window
;;;; - gravity: 位置计算策略，决定窗口显示位置
;;;; - style: 窗口样式（边框、颜色、光标等）
;;;;
;;;; 位置模式 (gravity):
;;;;   :center                          - 屏幕中央
;;;;   :top-display                     - 显示区域顶部
;;;;   :bottom-display                  - 显示区域底部
;;;;   :top                             - 源窗口上方
;;;;   :topright                        - 源窗口右上角
;;;;   :cursor                          - 光标位置（默认）
;;;;   :follow-cursor                   - 跟随光标移动
;;;;   :mouse-cursor                    - 鼠标位置
;;;;   :vertically-adjacent-window      - 垂直相邻窗口
;;;;   :vertically-adjacent-window-dynamic - 动态垂直相邻
;;;;   :horizontally-adjacent-window    - 水平相邻窗口
;;;;   :horizontally-above-window       - 水平上方窗口
;;;;
;;;; 样式选项 (style):
;;;;   :gravity         - 位置模式
;;;;   :use-border      - 是否显示边框
;;;;   :background-color - 背景颜色
;;;;   :offset-x        - X 轴偏移
;;;;   :offset-y        - Y 轴偏移
;;;;   :cursor-invisible - 是否隐藏光标
;;;;   :shape           - 边框形状
;;;;
;;;; 相关文件:
;;;;   - src/popup.lisp: 弹出窗口公共接口
;;;;   - src/ext/popup-menu.lisp: 弹出菜单实现
;;;;   - src/window/floating-window.lisp: 浮动窗口基类

(defpackage :lem/popup-window
  (:use :cl :lem)
  #+sbcl
  (:lock t))

(in-package :lem/popup-window)

;;; ============================================================================
;;; 常量定义
;;; ============================================================================

;; 边框大小（字符数）
(defconstant +border-size+ 1
  "弹出窗口边框大小（字符数）。")

;; 最小窗口宽度
(defconstant +min-width+ 3
  "弹出窗口最小宽度（字符数）。")

;; 最小窗口高度
(defconstant +min-height+ 1
  "弹出窗口最小高度（行数）。")

;;; ============================================================================
;;; 边距配置
;;; ============================================================================

;; 右侧额外边距
(defvar *extra-right-margin* 0
  "弹出窗口右侧额外边距。")

;; 宽度额外边距
(defvar *extra-width-margin* 0
  "弹出窗口宽度额外边距。")

;;; ============================================================================
;;; 泛型函数
;;; ============================================================================

(defgeneric adjust-for-redrawing (gravity popup-window)
  (:documentation "重绘前调整窗口位置。
                   用于 :follow-cursor 等需要动态更新位置的 gravity。")
  (:method (gravity popup-window)))

(defgeneric compute-popup-window-rectangle (gravity &key source-window width height border-size)
  (:documentation "计算弹出窗口的位置和大小。
                   
                   参数:
                     gravity - 位置策略对象
                     source-window - 源窗口
                     width - 请求的宽度
                     height - 请求的高度
                     border-size - 边框大小
                   
                   返回:
                     (x y width height) 列表"))

;;; ============================================================================
;;; Gravity 类层次
;;; ============================================================================

;; 基类：所有位置策略的父类
(defclass gravity ()
  ((offset-x :initarg :offset-x :accessor gravity-offset-x :initform 0
             :documentation "X 轴偏移量")
   (offset-y :initarg :offset-y :accessor gravity-offset-y :initform 0
             :documentation "Y 轴偏移量"))
  (:documentation "位置策略基类。"))

;; 具体位置策略类
(defclass gravity-center (gravity) ()
  (:documentation "屏幕中央。"))
(defclass gravity-top-display (gravity) ()
  (:documentation "显示区域顶部。"))
(defclass gravity-bottom-display (gravity) ()
  (:documentation "显示区域底部。"))
(defclass gravity-top (gravity) ()
  (:documentation "源窗口上方。"))
(defclass gravity-topright (gravity) ()
  (:documentation "源窗口右上角。"))
(defclass gravity-cursor (gravity) ()
  (:documentation "光标位置。"))
(defclass gravity-follow-cursor (gravity-cursor) ()
  (:documentation "跟随光标移动。"))
(defclass gravity-mouse-cursor (gravity) ()
  (:documentation "鼠标位置。"))
(defclass gravity-vertically-adjacent-window (gravity) ()
  (:documentation "垂直相邻窗口。"))
(defclass gravity-vertically-adjacent-window-dynamic (gravity) ()
  (:documentation "动态垂直相邻窗口。"))
(defclass gravity-horizontally-adjacent-window (gravity) ()
  (:documentation "水平相邻窗口。"))
(defclass gravity-horizontally-above-window (gravity) ()
  (:documentation "水平上方窗口。"))

;;; ============================================================================
;;; Popup-Window 类
;;; ============================================================================

(defclass popup-window (floating-window)
  ((gravity
    :initarg :gravity
    :reader popup-window-gravity
    :documentation "窗口的位置策略")
   (source-window
    :initarg :source-window
    :reader popup-window-source-window
    :documentation "触发弹出窗口的源窗口")
   (base-width
    :initarg :base-width
    :reader popup-window-base-width
    :documentation "基础宽度（不含边框）")
   (base-height
    :initarg :base-height
    :reader popup-window-base-height
    :documentation "基础高度（不含边框）")
   (style
    :initarg :style
    :reader popup-window-style
    :documentation "窗口样式配置"))
  (:documentation "弹出窗口类。
                   继承自 floating-window，提供可配置的位置和样式。"))

(defmethod lem:window-parent ((window popup-window))
  "返回弹出窗口的父窗口（源窗口）。"
  (popup-window-source-window window))

;;; ============================================================================
;;; Gravity 工具函数
;;; ============================================================================

(defun ensure-gravity (gravity)
  "将 gravity 关键字转换为 gravity 对象。
   
   参数:
     gravity - 关键字或 gravity 对象
   
   支持的关键字:
     :center, :top-display, :bottom-display, :top, :topright,
     :cursor, :follow-cursor, :mouse-cursor,
     :vertically-adjacent-window, :vertically-adjacent-window-dynamic,
     :horizontally-adjacent-window, :horizontally-above-window
   
   返回:
     gravity 对象"
  (if (typep gravity 'gravity)
      gravity
      (ecase gravity
        (:center (make-instance 'gravity-center))
        (:top-display (make-instance 'gravity-top-display))
        (:bottom-display (make-instance 'gravity-bottom-display))
        (:top (make-instance 'gravity-top))
        (:topright (make-instance 'gravity-topright))
        (:cursor (make-instance 'gravity-cursor))
        (:follow-cursor (make-instance 'gravity-follow-cursor))
        (:mouse-cursor (make-instance 'gravity-mouse-cursor))
        (:vertically-adjacent-window (make-instance 'gravity-vertically-adjacent-window))
        (:vertically-adjacent-window-dynamic (make-instance 'gravity-vertically-adjacent-window-dynamic))
        (:horizontally-adjacent-window (make-instance 'gravity-horizontally-adjacent-window))
        (:horizontally-above-window (make-instance 'gravity-horizontally-above-window)))))

(defmethod adjust-for-redrawing ((gravity gravity-follow-cursor) popup-window)
  (destructuring-bind (x y width height)
      (compute-popup-window-rectangle (popup-window-gravity popup-window)
                                      :source-window (popup-window-source-window popup-window)
                                      :width (popup-window-base-width popup-window)
                                      :height (popup-window-base-height popup-window)
                                      :border-size (window-border popup-window))
    (lem-core::window-set-size popup-window width height)
    (lem-core::window-set-pos popup-window
                              (+ x (window-border popup-window))
                              (+ y (window-border popup-window)))))

(defmethod compute-popup-window-rectangle :around ((gravity gravity) &key &allow-other-keys)
  (destructuring-bind (x y width height)
      (call-next-method)
    (list (+ x (gravity-offset-x gravity))
          (+ y (gravity-offset-y gravity))
          (max width 1)
          (max height 1))))

(defmethod compute-popup-window-rectangle ((gravity gravity-center)
                                           &key width height &allow-other-keys)
  (let ((x (- (floor (display-width) 2)
              (floor width 2)))
        (y (- (floor (display-height) 2)
              (floor height 2))))
    (list x y width height)))

(defmethod compute-popup-window-rectangle ((gravity gravity-cursor)
                                           &key source-window width height border-size)
  (let* ((border-size (or border-size 0))
         (b2 (* border-size 2))
         (disp-w (max (- (display-width)  b2 *extra-right-margin*)
                      +min-width+))
         (disp-h (max (- (display-height) b2)
                      +min-height+))
         (width  (max (+ width *extra-width-margin*)
                      +min-width+))
         (height (max height
                      +min-height+))
         (x (+ (window-x source-window)
               (window-cursor-x source-window)))
         (y (max (min (+ (window-y source-window)
                         (window-cursor-y source-window)
                         border-size)
                      (1- (display-height)))
                 0))
         (w width)
         (h height))
    ;; calc y and h
    (when (> (+ y height) disp-h)
      (decf h (- (+ y height) disp-h)))
    (when (< h (min height (floor disp-h 3)))
      (setf h height)
      (decf y (+ height b2 1)))
    (when (< y 0)
      (decf h (- y))
      (setf y 0))
    (when (<= h 0) ; for safety
      (setf y 0)
      (setf h (min height disp-h)))
    ;; calc x and w
    (when (> (+ x width) disp-w)
      (decf x (- (+ x width) disp-w)))
    (when (< x 0)  ; for safety
      (setf x 0)
      (setf w (min width disp-w)))
    (list x y w h)))

(defmethod compute-popup-window-rectangle ((gravity gravity-mouse-cursor) &key width height
                                                                          &allow-other-keys)
  (multiple-value-bind (x y)
      (lem-if:get-mouse-position (lem:implementation))
    (list x y width height)))

(defmethod compute-popup-window-rectangle ((gravity gravity-top-display)
                                           &key width height
                                           &allow-other-keys)
  (let* ((x (- (floor (display-width) 2)
               (floor width 2)))
         (y 1))
    (list x y (1- width) height)))

(defmethod compute-popup-window-rectangle ((gravity gravity-bottom-display)
                                           &key width height
                                           &allow-other-keys)
  (let* ((x (- (floor (display-width) 2)
               (floor width 2)))
         (y (- (display-height) height)))
    (list x y (1- width) height)))

(defmethod compute-popup-window-rectangle ((gravity gravity-top) &key source-window width height
                                                                 &allow-other-keys)
  (let* ((x (- (floor (display-width) 2)
               (floor width 2)))
         (y (+ (window-y source-window) 1)))
    (list x y width height)))

(defmethod compute-popup-window-rectangle ((gravity gravity-topright)
                                           &key source-window width height border-size
                                           &allow-other-keys)
  (let* ((b2 (* (or border-size 0) 2))
         (win-x (window-x source-window))
         (win-y (window-y source-window))
         (win-w (max (- (window-width  source-window) b2 2)
                     +min-width+))
         (win-h (max (- (window-height source-window) b2)
                     +min-height+))
         (width  (max (+ width *extra-width-margin*)
                      +min-width+))
         (height (max height
                      +min-height+))
         (x (+ win-x (- win-w width)))
         (y (+ win-y 1))
         (w width)
         (h height))
    ;; calc y and h
    (when (> (+ y height) (+ win-y win-h))
      (decf h (- (+ y height) (+ win-y win-h))))
    (when (<= h 0)    ; for safety
      (setf y win-y)
      (setf h (min height win-h)))
    ;; calc x and w
    (when (< x win-x) ; for safety
      (setf x win-x)
      (setf w (min width win-w)))
    (list x y w h)))

(defmethod compute-popup-window-rectangle ((gravity gravity-vertically-adjacent-window)
                                           &key source-window width height #+(or)border-size
                                           &allow-other-keys)
  (let ((x (+ (window-x source-window)
              (window-width source-window)))
        (y (window-y source-window)))
    (list x y width height)))

(defmethod compute-popup-window-rectangle ((gravity gravity-vertically-adjacent-window-dynamic)
                                           &key source-window width height #+(or)border-size
                                           &allow-other-keys)
  (let ((x (+ (window-x source-window) (window-width source-window)))
        (y (window-y source-window)))
    (when (>= (+ x width) (display-width))
      (setf (gravity-offset-x gravity) (- (gravity-offset-x gravity))
            x (max 0 (- (window-x source-window) width 1))))
    (when (>= (+ y height) (display-height))
      (setf (gravity-offset-y gravity) 0
            y (max 0 (- (display-height) height 2))))
    (list x y width height)))

(defmethod compute-popup-window-rectangle ((gravity gravity-horizontally-adjacent-window)
                                           &key source-window width height border-size
                                           &allow-other-keys)
  (let ((x (- (window-x source-window) border-size))
        (y (+ (window-y source-window)
              (window-height source-window)
              border-size)))
    ;; workaround: cases that extend beyond the screen
    (when (< (display-height) (+ y height))
      (setf height (- (display-height) y 1)))
    (list x
          y
          (max width (window-width source-window))
          height)))

(defmethod compute-popup-window-rectangle ((gravity gravity-horizontally-above-window)
                                           &key source-window width height border-size
                                           &allow-other-keys)
  (let ((x (- (window-x source-window) border-size))
        (y (- (window-y source-window)
              height
              border-size)))
    ;; workaround: cases that extend beyond the screen
    (when (< (display-height) (+ y height))
      (setf height (- (display-height) y 1)))
    (list x
          y
          (max width (window-width source-window))
          height)))

(defun compute-buffer-width (buffer)
  (with-point ((point (buffer-start-point buffer)))
    (loop :maximize (point-column (line-end point))
          :while (line-offset point 1))))

(defun compute-buffer-height (buffer)
  (buffer-nlines buffer))

(defun compute-buffer-size (buffer)
  (list (compute-buffer-width buffer)
        (compute-buffer-height buffer)))

(defmethod window-redraw ((popup-window popup-window) force)
  (adjust-for-redrawing (popup-window-gravity popup-window) popup-window)
  (call-next-method))

(defstruct style
  (gravity :cursor)
  (use-border t)
  (background-color nil)
  (offset-x 0)
  (offset-y 0)
  (cursor-invisible nil)
  shape)

(defun merge-style (style &key (gravity nil gravity-p)
                               (use-border nil use-border-p)
                               (background-color nil background-color-p)
                               (cursor-invisible nil cursor-invisible-p)
                               (shape nil shape-p))
  (make-style :gravity (if gravity-p
                           gravity
                           (style-gravity style))
              :use-border (if use-border-p
                              use-border
                              (style-use-border style))
              :background-color (if background-color-p
                                    background-color
                                    (style-background-color style))
              :offset-x (style-offset-x style)
              :offset-y (style-offset-y style)
              :cursor-invisible (if cursor-invisible-p
                                    cursor-invisible
                                    (style-cursor-invisible style))
              :shape (if shape-p
                         shape
                         (style-shape style))))

(defun ensure-style (style)
  (cond ((null style)
         (make-style))
        ((style-p style)
         style)
        (t
         (apply #'make-style style))))

(defun make-popup-window (&key (source-window (alexandria:required-argument :source-window))
                               (buffer (alexandria:required-argument :buffer))
                               (width (alexandria:required-argument :width))
                               (height (alexandria:required-argument :height))
                               (clickable t)
                               style)
  (let* ((style (ensure-style style))
         (border-size (if (style-use-border style) +border-size+ 0))
         (gravity (ensure-gravity (style-gravity style))))
    (setf (gravity-offset-x gravity) (style-offset-x style)
          (gravity-offset-y gravity) (style-offset-y style))
    (destructuring-bind (x y w h)
        (compute-popup-window-rectangle gravity
                                        :source-window source-window
                                        :width width
                                        :height height
                                        :border-size border-size)
      (make-instance 'popup-window
                     :buffer buffer
                     :x (+ x border-size)
                     :y (+ y border-size)
                     :width  w
                     :height h
                     :use-modeline-p nil
                     :gravity gravity
                     :source-window source-window
                     :base-width  width
                     :base-height height
                     :border border-size
                     :border-shape (style-shape style)
                     :background-color (style-background-color style)
                     :cursor-invisible (style-cursor-invisible style)
                     :clickable clickable
                     :style style))))

(defun update-popup-window (&key (source-window (alexandria:required-argument :source-window))
                                 (width (alexandria:required-argument :width))
                                 (height (alexandria:required-argument :height))
                                 (destination-window
                                  (alexandria:required-argument :destination-window)))
  (let* ((style (popup-window-style destination-window))
         (border-size (if (style-use-border style) +border-size+ 0))
         (gravity (ensure-gravity (style-gravity style))))
    (setf (gravity-offset-x gravity) (style-offset-x style)
          (gravity-offset-y gravity) (style-offset-y style))
    (destructuring-bind (x y w h)
        (compute-popup-window-rectangle gravity
                                        :source-window source-window
                                        :width width
                                        :height height
                                        :border-size border-size)
      ;; XXX: workaround for context-menu
      (unless (typep gravity 'gravity-cursor)
        (lem-core::window-set-pos destination-window
                                  (+ x border-size)
                                  (+ y border-size)))
      (lem-core::window-set-size destination-window w h)
      destination-window)))
