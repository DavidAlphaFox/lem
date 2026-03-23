;;;; interface.lisp - Lem 前端抽象层
;;;;
;;;; 本文件定义了 Lem 编辑器的前端抽象接口层。
;;;; 所有前端实现（SDL2、NCurses、Webview 等）都通过此接口与核心交互。
;;;;
;;;; 核心概念:
;;;; - implementation: 前端实现类，描述前端能力和行为
;;;; - lem-if:* 泛型函数: 前端必须实现的接口方法
;;;;
;;;; 前端类型:
;;;; - SDL2: 桌面图形界面（硬件加速渲染）
;;;; - NCurses: 终端界面
;;;; - Webview: 嵌入式浏览器界面
;;;; - Server: JSON-RPC 服务端（远程界面）
;;;;
;;;; 相关文件:
;;;;   - frontends/sdl2/main.lisp: SDL2 实现
;;;;   - frontends/ncurses/ncurses.lisp: NCurses 实现
;;;;   - frontends/server/main.lisp: JSON-RPC 实现

(in-package :lem-core)

;;; ============================================================================
;;; 前端实现类
;;; ============================================================================

;; 当前活动的前端实现实例
(defvar *implementation*)

(defclass implementation ()
  ((name
    :initform (alexandria:required-argument :name)
    :initarg :name
    :reader implementation-name
    :documentation "前端实现名称（如 :sdl2, :ncurses, :webview）")
   
   (redraw-after-modifying-floating-window
    :initform nil
    :initarg :redraw-after-modifying-floating-window
    :reader redraw-after-modifying-floating-window
    :documentation "修改浮动窗口后是否需要重绘")
   
   (support-floating-window
    :initform t
    :initarg :support-floating-window
    :reader support-floating-window
    :documentation "是否支持浮动窗口")
   
   (window-left-margin
    :initform 1
    :initarg :window-left-margin
    :reader window-left-margin
    :documentation "窗口左边距（字符数）")
   
   (window-bottom-margin
    :initform 1
    :initarg :window-bottom-margin
    :reader window-bottom-margin
    :documentation "窗口底边距（字符数）")
   
   (html-support
    :initform nil
    :initarg :html-support
    :reader html-support-p
    :documentation "是否支持 HTML 渲染（用于 Webview）")
   
   (no-force-needed
    :initform nil
    :initarg :no-force-needed
    :reader no-force-needed-p
    :documentation "当 T 时，redraw-display 的 force 参数被忽略。
                   在 ncurses 等环境中，修改上层窗口需要重绘下层窗口，
                   此时需设置 force 为 T。
                   在 DOM 一对一渲染时不需要重绘。")
   
   (underline-color-support
    :initform nil
    :initarg :underline-color-support
    :reader underline-color-support-p
    :documentation "是否支持与前景色不同的下划线颜色（终端中通常为 nil）")
   
   (support-pixel-positioning
    :initform nil
    :initarg :support-pixel-positioning
    :reader support-pixel-positioning-p
    :documentation "是否支持像素级定位浮动窗口。"))
  
  (:documentation "前端实现基类。
                   所有前端实现（SDL2、NCurses、Webview 等）都继承此类。
                   
                   示例:
                   (defclass sdl2 (lem:implementation) ())"))

;;; ============================================================================
;;; 前端选择
;;; ============================================================================

(defun get-default-implementation (&key implementation)
  "获取默认前端实现实例。
   
   参数:
     implementation - 可选的前端名称关键字（如 :sdl2, :ncurses, :webview）
   
   选择顺序:
     1. 用户指定的前端（如果存在）
     2. :webview
     3. :ncurses
     4. :sdl2
   
   返回: implementation 实例
   
   错误: 如果没有找到任何前端实现，抛出错误"
  (let ((classes (c2mop:class-direct-subclasses (find-class 'implementation)))
        implementation-fallback
        class)
    (when (>= 0 (length classes))
      (error "Implementation does not exist.~
                             (probably because you didn't load the lem-ncurses system)"))

    ;; 设置回退列表：如果指定的前端不存在，按顺序尝试
    (setf implementation-fallback
          (mapcar (lambda (impl)
                    (find impl classes :test 'string= :key 'class-name))
                  ;; 始终优先尝试用户指定的前端
                  (list implementation :webview :ncurses :sdl2)))

    ;; 选择第一个可用的前端
    (setf class (funcall #'some #'identity implementation-fallback))

    (if (string= (class-name class) implementation)
         (log:info "Using interface: ~A" implementation)
         (log:warn "User specified non-existant interface ~A; Using ~A instead.
Available interfaces: ~A"
                   implementation class classes))
    
    (if class
      (make-instance class)
      (error "No interfaces found (is lem compiled with an interface?)"))))

;;; ============================================================================
;;; 显示相关变量
;;; ============================================================================

;; 绘图窗口的背景颜色（由前端设置）
(defvar lem-if:*background-color-of-drawing-window* nil)

;;; ============================================================================
;;; 光标类型
;;; ============================================================================

(deftype cursor-type ()
  "光标类型定义。
   :box     - 方块光标（默认）
   :bar     - 竖线光标（插入模式）
   :underline - 下划线光标"
  '(member :box :bar :underline))

;;; ============================================================================
;;; 前端接口泛型函数 (lem-if:*)
;;; 
;;; 所有前端必须实现这些泛型函数。
;;; 前端实现位于 frontends/ 目录下。
;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; 生命周期
;;; ----------------------------------------------------------------------------

(defgeneric lem-if:invoke (implementation function)
  (:documentation "启动前端事件循环。
                   IMPLEMENTATION: 前端实例
                   FUNCTION: 接收可选的初始化和终结函数的回调"))

;;; ----------------------------------------------------------------------------
;;; 颜色管理
;;; ----------------------------------------------------------------------------

(defgeneric lem-if:get-background-color (implementation)
  (:documentation "获取背景颜色。"))

(defgeneric lem-if:get-foreground-color (implementation)
  (:documentation "获取前景颜色。"))

(defgeneric lem-if:update-foreground (implementation color-name)
  (:documentation "更新前景颜色。"))

(defgeneric lem-if:update-background (implementation color-name)
  (:documentation "更新背景颜色。"))

(defgeneric lem-if:update-cursor-shape (implementation cursor-type)
  (:documentation "更新光标形状。
                   CURSOR-TYPE: :box, :bar, 或 :underline")
  (:method (implementation cursor-type)))

;;; ----------------------------------------------------------------------------
;;; 显示属性
;;; ----------------------------------------------------------------------------

(defgeneric lem-if:display-width (implementation)
  (:documentation "获取显示宽度（字符数）。"))

(defgeneric lem-if:display-height (implementation)
  (:documentation "获取显示高度（字符数）。"))

(defgeneric lem-if:display-title (implementation)
  (:documentation "获取窗口标题。"))

(defgeneric lem-if:set-display-title (implementation title)
  (:documentation "设置窗口标题。"))

(defgeneric lem-if:display-fullscreen-p (implementation)
  (:documentation "检查是否全屏。"))

(defgeneric lem-if:set-display-fullscreen-p (implementation fullscreen-p)
  (:documentation "设置全屏状态。"))

(defgeneric lem-if:maximize-frame (implementation)
  (:documentation "最大化窗口。")
  (:method (implementation)))

(defgeneric lem-if:minimize-frame (implementation)
  (:documentation "最小化窗口。")
  (:method (implementation)))

;;; ----------------------------------------------------------------------------
;;; 视图管理
;;; 
;;; View 是前端中表示编辑器窗口的对象。
;;; 每个 Lem Window 对应一个前端 View。
;;; ----------------------------------------------------------------------------

(defgeneric lem-if:make-view (implementation window x y width height use-modeline)
  (:documentation "创建视图对象。
                   WINDOW: Lem 窗口对象
                   X, Y: 字符坐标
                   WIDTH, HEIGHT: 字符尺寸
                   USE-MODELINE: 是否显示模式行"))

(defgeneric lem-if:view-width (implementation view)
  (:documentation "获取视图宽度。"))

(defgeneric lem-if:view-height (implementation view)
  (:documentation "获取视图高度。"))

(defgeneric lem-if:delete-view (implementation view)
  (:documentation "删除视图。"))

(defgeneric lem-if:clear (implementation view)
  (:documentation "清除视图内容。"))

(defgeneric lem-if:set-view-size (implementation view width height)
  (:documentation "设置视图大小（字符单位）。"))

(defgeneric lem-if:set-view-pos (implementation view x y)
  (:documentation "设置视图位置（字符单位）。"))

(defgeneric lem-if:make-view-with-pixels (implementation window x y width height
                                          pixel-x pixel-y pixel-width pixel-height
                                          use-modeline)
  (:documentation "使用字符和像素坐标创建视图。
                   X, Y, WIDTH, HEIGHT: 字符单位
                   PIXEL-X, PIXEL-Y, PIXEL-WIDTH, PIXEL-HEIGHT: 像素单位（可为 nil 自动计算）")
  (:method (implementation window x y width height pixel-x pixel-y pixel-width pixel-height use-modeline)
    (declare (ignore pixel-x pixel-y pixel-width pixel-height))
    (lem-if:make-view implementation window x y width height use-modeline)))

(defgeneric lem-if:set-view-pos-pixels (implementation view x y pixel-x pixel-y)
  (:documentation "使用字符和像素坐标设置视图位置。")
  (:method (implementation view x y pixel-x pixel-y)
    (declare (ignore pixel-x pixel-y))
    (lem-if:set-view-pos implementation view x y)))

(defgeneric lem-if:set-view-size-pixels (implementation view width height pixel-width pixel-height)
  (:documentation "使用字符和像素坐标设置视图大小。")
  (:method (implementation view width height pixel-width pixel-height)
    (declare (ignore pixel-width pixel-height))
    (lem-if:set-view-size implementation view width height)))

;;; ----------------------------------------------------------------------------
;;; 渲染
;;; ----------------------------------------------------------------------------

(defgeneric lem-if:redraw-view-before (implementation view)
  (:documentation "视图重绘前调用。")
  (:method (implementation view)))

(defgeneric lem-if:redraw-view-after (implementation view)
  (:documentation "视图重绘后调用。")
  (:method (implementation view)))

(defgeneric lem-if:will-update-display (implementation)
  (:documentation "显示更新前调用。")
  (:method (implementation)))

(defgeneric lem-if:update-display (implementation)
  (:documentation "更新显示。将渲染内容刷新到屏幕。"))

;;; ----------------------------------------------------------------------------
;;; 弹出菜单
;;; ----------------------------------------------------------------------------

(defgeneric lem-if:display-popup-menu (implementation items
                                       &key action-callback
                                            print-spec
                                            style
                                         max-display-items)
  (:documentation "显示弹出菜单。
                  ITEMS: 菜单项列表
                  ACTION-CALLBACK: 选择时的回调函数
                  PRINT-SPEC: 打印规范
                  STYLE: 菜单样式
                  MAX-DISPLAY-ITEMS: 最大显示项数"))

(defgeneric lem-if:popup-menu-update
    (implementation popup-menu items &key print-spec max-display-items keep-focus)
  (:documentation "更新弹出菜单内容。"))

(defgeneric lem-if:popup-menu-quit (implementation popup-menu)
  (:documentation "关闭弹出菜单。"))

(defgeneric lem-if:popup-menu-down (implementation popup-menu)
  (:documentation "移动到下一项。"))

(defgeneric lem-if:popup-menu-up (implementation popup-menu)
  (:documentation "移动到上一项。"))

(defgeneric lem-if:popup-menu-first (implementation popup-menu)
  (:documentation "移动到第一项。"))

(defgeneric lem-if:popup-menu-last (implementation popup-menu)
  (:documentation "移动到最后一项。"))

(defgeneric lem-if:popup-menu-select (implementation popup-menu)
  (:documentation "选择当前项。"))

(defgeneric lem-if:display-context-menu (implementation context-menu style)
  (:documentation "显示上下文菜单。")
  (:method (implementation context-menu style)))

;;; ----------------------------------------------------------------------------
;;; 剪贴板
;;; ----------------------------------------------------------------------------

(defgeneric lem-if:clipboard-paste (implementation)
  (:documentation "从剪贴板粘贴。")
  (:method (implementation)))

(defgeneric lem-if:clipboard-copy (implementation text)
  (:documentation "复制文本到剪贴板。")
  (:method (implementation text)))

;;; ----------------------------------------------------------------------------
;;; 字体管理
;;; ----------------------------------------------------------------------------

(defgeneric lem-if:increase-font-size (implementation)
  (:documentation "增大字体。")
  (:method (implementation)))

(defgeneric lem-if:decrease-font-size (implementation)
  (:documentation "减小字体。")
  (:method (implementation)))

(defgeneric lem-if:set-font-name (implementation font-name)
  (:documentation "设置字体名称。")
  (:method (implementation font-name) '()))

(defgeneric lem-if:set-font-size (implementation size)
  (:documentation "设置字体大小。")
  (:method (implementation size)))

(defgeneric lem-if:resize-display-before (implementation)
  (:documentation "显示大小调整前调用。")
  (:method (implementation)))

(defgeneric lem-if:get-font-list (implementation)
  (:documentation "获取可用字体列表。")
  (:method (implementation) '()))

(defgeneric lem-if:get-font (implementation)
  (:documentation "获取当前字体信息。")
  (:method (implementation) (values nil nil)))

;;; ----------------------------------------------------------------------------
;;; 输入处理
;;; ----------------------------------------------------------------------------

(defgeneric lem-if:get-mouse-position (implementation)
  (:documentation "获取鼠标位置。")
  (:method (implementation)
    (values -1 -1)))

(defgeneric lem-if:get-char-width (implementation)
  (:documentation "获取字符宽度（像素）。"))

(defgeneric lem-if:get-char-height (implementation)
  (:documentation "获取字符高度（像素）。"))

;;; ----------------------------------------------------------------------------
;;; 渲染
;;; ----------------------------------------------------------------------------

(defgeneric lem-if:render-line (implementation view x y objects height)
  (:documentation "渲染一行文本。
                  VIEW: 视图对象
                  X, Y: 起始坐标
                  OBJECTS: 渲染对象列表
                  HEIGHT: 行高"))

(defgeneric lem-if:render-line-on-modeline (implementation view left-objects right-objects
                                            default-attribute height)
  (:documentation "渲染模式行。
                  LEFT-OBJECTS: 左侧对象
                  RIGHT-OBJECTS: 右侧对象
                  DEFAULT-ATTRIBUTE: 默认属性
                  HEIGHT: 行高"))

(defgeneric lem-if:object-width (implementation drawing-object)
  (:documentation "获取绘制对象宽度。"))

(defgeneric lem-if:object-height (implementation drawing-object)
  (:documentation "获取绘制对象高度。"))

(defgeneric lem-if:clear-to-end-of-window (implementation view y)
  (:documentation "清除窗口从指定行到末尾。"))

(defgeneric lem-if:js-eval (implementation view code &key wait)
  (:documentation "在视图中执行 JavaScript 代码（仅 HTML 支持的前端）。
                  CODE: JavaScript 代码字符串
                  WAIT: 是否等待执行完成")
  (:method (implementation view code &key wait)
    (declare (ignore wait))
    (error "js-eval not implemented for this frontend")))

;;; ============================================================================
;;; 辅助函数
;;; ============================================================================

(defvar *display-background-mode* nil
  "显示背景模式，:light 或 :dark。")

(defun implementation ()
  "获取当前前端实现实例。"
  *implementation*)

(defmacro with-implementation (implementation &body body)
  "在指定前端实现的上下文中执行代码体。
   设置 *implementation* 并确保在线程中正确传递。"
  `(let* ((*implementation* ,implementation)
          (bt2:*default-special-bindings*
            (acons '*implementation*
                   *implementation*
                   bt2:*default-special-bindings*)))
     ,@body))

(defun display-background-mode ()
  "获取显示背景模式（:light 或 :dark）。
   如果未设置，则根据背景颜色自动判断。"
  (or *display-background-mode*
      (if (light-color-p (lem-if:get-background-color (implementation)))
          :light
          :dark)))

(defun set-display-background-mode (mode)
  "设置显示背景模式。
   MODE: :light, :dark 或 nil（自动检测）"
  (check-type mode (member :light :dark nil))
  (setf *display-background-mode* mode))

(defun set-foreground (name)
  "设置前景颜色。"
  (when name
    (lem-if:update-foreground (implementation) name)))

(defun set-background (name)
  "设置背景颜色。"
  (when name
    (lem-if:update-background (implementation) name)))

(defun attribute-foreground-color (attribute)
  "获取属性的前景颜色。
   如果属性未指定，返回默认前景颜色。"
  (or (and attribute
           (parse-color (attribute-foreground attribute)))
      (lem-if:get-foreground-color (implementation))))

(defun attribute-background-color (attribute)
  "获取属性的背景颜色。
   如果属性未指定，返回默认背景颜色。"
  (or (and attribute
           (parse-color (attribute-background attribute)))
      (lem-if:get-background-color (implementation))))

(defun attribute-foreground-with-reverse (attribute)
  "获取属性的前景颜色，考虑反色标志。
   如果设置了反色，返回背景颜色。"
  (if (and attribute (attribute-reverse attribute))
      (attribute-background-color attribute)
      (attribute-foreground-color attribute)))

(defun attribute-background-with-reverse (attribute)
  "获取属性的背景颜色，考虑反色标志。
   如果设置了反色，返回前景颜色。"
  (if (and attribute (attribute-reverse attribute))
      (attribute-foreground-color attribute)
      (attribute-background-color attribute)))

;;; ----------------------------------------------------------------------------
;;; 便捷函数
;;; ----------------------------------------------------------------------------

(defun display-width ()
  "获取显示宽度（字符数）。"
  (lem-if:display-width (implementation)))

(defun display-height ()
  "获取显示高度（字符数）。"
  (lem-if:display-height (implementation)))

(defun display-title ()
  "获取窗口标题。"
  (lem-if:display-title (implementation)))

(defun (setf display-title) (title)
  "设置窗口标题。"
  (lem-if:set-display-title (implementation) title))

(defun display-fullscreen-p ()
  "检查是否全屏。"
  (lem-if:display-fullscreen-p (implementation)))

(defun (setf display-fullscreen-p) (fullscreen-p)
  "设置全屏状态。"
  (lem-if:set-display-fullscreen-p (implementation) fullscreen-p))

(defgeneric lem-if:update-screen-size (implementation)
  (:documentation "更新屏幕大小。在字体更改后调用。")
  (:method (implementation)))

(defun set-font-name (font-name)
  "设置字体名称并更新屏幕大小。"
  (lem-if:set-font-name (implementation) font-name)
  (lem-if:update-screen-size (implementation)))

(defun set-font-size (font-size)
  "设置字体大小并更新屏幕大小。"
  (lem-if:set-font-size (implementation) font-size)
  (lem-if:update-screen-size (implementation)))

(defun set-font (&key (name nil name-p) (size nil size-p))
  "设置字体名称和/或大小。
   NAME: 字体名称（可选）
   SIZE: 字体大小（可选）"
  (when name-p (lem-if:set-font-name (implementation) name))
  (when size-p (lem-if:set-font-size (implementation) size))
  (lem-if:update-screen-size (implementation)))

(defun invoke-frontend (function &key (implementation
                                       (get-default-implementation)))
  "启动前端。
   FUNCTION: 接收可选初始化和终结函数的回调
   IMPLEMENTATION: 使用的前端实现（默认自动选择）"
  (setf *implementation* implementation)
  (lem-if:invoke implementation function))

(defun lem-if:get-font-by-name-and-style (name style)
  "按名称和样式查找字体。
   NAME: 字体名称
   STYLE: 字体样式（如 'Regular', 'Bold', 'Italic'）
   
   返回匹配的字体文件路径。"
  (flet ((equal-downcase (s1 s2) (equal (string-downcase s1) (string-downcase s2))))
    (let ((fonts (loop :for font in (lem-if:get-font-list (implementation))
                       :for style-termination := (format nil "~a." style)
                       :when (and (search name font :test #'equal-downcase)
                                  (search style-termination font :test #'equal-downcase))
                       :collect font)))
      (if fonts
          (car fonts)
          (error "font not found for font-name=~s and style=~s" name style)))))
