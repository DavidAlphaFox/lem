;;;; popup.lisp - Lem 编辑器弹出消息和菜单系统
;;;;
;;;; 本文件实现 Lem 的弹出界面系统，负责：
;;;; - 弹出消息显示（如通知、警告等）
;;;; - 弹出菜单（如补全列表、命令选择等）
;;;;
;;;; 核心概念:
;;;; - popup-message: 临时显示的消息，可设置超时自动消失
;;;; - popup-menu: 交互式菜单，支持键盘导航和选择
;;;;
;;;; 弹出菜单位置 (gravity):
;;;;   :center              - 屏幕中央
;;;;   :top-display         - 显示区域顶部
;;;;   :bottom-display      - 显示区域底部
;;;;   :top                 - 源窗口上方
;;;;   :topright            - 源窗口右上角
;;;;   :cursor              - 光标位置
;;;;   :follow-cursor       - 跟随光标移动
;;;;   :mouse-cursor        - 鼠标位置
;;;;   :vertically-adjacent-window - 垂直相邻窗口
;;;;   :horizontally-adjacent-window - 水平相邻窗口
;;;;
;;;; 相关文件:
;;;;   - src/ext/popup-window.lisp: 弹出窗口实现
;;;;   - src/ext/popup-menu.lisp: 弹出菜单实现
;;;;   - src/ext/popup-message.lisp: 弹出消息实现
;;;;   - src/interface.lisp: 前端接口

(in-package :lem-core)

;;; ============================================================================
;;; 配置参数
;;; ============================================================================

;; 默认弹出消息超时时间（秒）
(defparameter *default-popup-message-timeout* 5
  "弹出消息的默认显示时间（秒）。")

;;; ============================================================================
;;; 弹出消息接口
;;; ============================================================================

;; 当前弹出消息器实例
(defvar lem-core/popup-message-interface:*popup-messenger* nil
  "当前活动的弹出消息器实例。")

(defgeneric lem-core/popup-message-interface:display-popup-message
    (popup-messenger
     buffer-or-string
     &key timeout
          destination-window
          source-window
          style)
  (:documentation "显示弹出消息。
                   
                   参数:
                     popup-messenger - 弹出消息器
                     buffer-or-string - 要显示的内容（缓冲区或字符串）
                     timeout - 显示时间（秒），nil 表示永久显示
                     destination-window - 目标窗口
                     source-window - 源窗口
                     style - 显示样式"))

(defgeneric lem-core/popup-message-interface:delete-popup-message (popup-messenger popup-message)
  (:documentation "删除弹出消息。
                   
                   参数:
                     popup-messenger - 弹出消息器
                     popup-message - 要删除的消息对象"))

;;; ============================================================================
;;; 公共弹出消息函数
;;; ============================================================================

(defun display-popup-message (buffer-or-string
                              &key (timeout *default-popup-message-timeout*)
                                   destination-window
                                   source-window
                                   style)
  "显示弹出消息。
   
   参数:
     buffer-or-string - 要显示的内容（缓冲区或字符串）
     timeout - 显示时间（秒），默认 5 秒
     destination-window - 目标窗口（可选）
     source-window - 源窗口（可选）
     style - 显示样式（可选）
   
   返回:
     弹出消息对象（可用于后续删除）
   
   示例:
     ;; 显示简单消息
     (display-popup-message \"操作完成\")
     
     ;; 显示缓冲区内容
     (display-popup-message (get-buffer \"*help*\") :timeout nil)"
  (lem-core/popup-message-interface:display-popup-message
   lem-core/popup-message-interface:*popup-messenger*
   buffer-or-string
   :timeout timeout
   :destination-window destination-window
   :source-window source-window
   :style style))

(defun delete-popup-message (popup-message)
  "删除弹出消息。
   
   参数:
     popup-message - 要删除的消息对象"
  (lem-core/popup-message-interface:delete-popup-message
   lem-core/popup-message-interface:*popup-messenger*
   popup-message))

;;; ============================================================================
;;; 弹出菜单
;;; ============================================================================

(defun display-popup-menu (items
                           &rest args
                           &key action-callback
                                print-spec
                                style
                                max-display-items)
  "显示弹出菜单。
   
   参数:
     items - 菜单项列表
     action-callback - 选择回调函数，接收选中项作为参数
     print-spec - 打印规范函数，将菜单项转换为字符串显示
     style - 显示样式（plist 或 style 结构体）
     max-display-items - 最大显示项数
   
   样式选项 (style):
     :use-border      - 是否使用边框（默认 t）
     :offset-y        - Y 轴偏移
     :gravity         - 位置（默认 :cursor）
     :background-color - 背景颜色
     :offset-x        - X 轴偏移
     :cursor-invisible - 是否隐藏光标
     :shape           - 边框形状
   
   gravity 可能的值:
     :center                          - 屏幕中央
     :top-display                     - 显示区域顶部
     :bottom-display                  - 显示区域底部
     :top                             - 源窗口上方
     :topright                        - 源窗口右上角
     :cursor                          - 光标位置
     :follow-cursor                   - 跟随光标
     :mouse-cursor                    - 鼠标位置
     :vertically-adjacent-window      - 垂直相邻窗口
     :vertically-adjacent-window-dynamic - 动态垂直相邻
     :horizontally-adjacent-window    - 水平相邻窗口
     :horizontally-above-window       - 水平上方窗口
   
   示例:
     ;; 简单菜单
     (display-popup-menu '(\"选项1\" \"选项2\" \"选项3\")
       :action-callback (lambda (item) (message \"选中: ~A\" item)))
     
     ;; 带样式的菜单
     (display-popup-menu items
       :style '(:use-border t :gravity :bottom-display)
       :max-display-items 10)"
  (declare (ignore action-callback print-spec style max-display-items))
  (apply #'lem-if:display-popup-menu (implementation)
         items
         args))

;;; ============================================================================
;;; 弹出菜单操作
;;; ============================================================================

(defun popup-menu-update (popup-menu items &rest args &key print-spec max-display-items keep-focus)
  "更新弹出菜单内容。
   
   参数:
     popup-menu - 要更新的菜单对象
     items - 新的菜单项列表
     print-spec - 打印规范函数
     max-display-items - 最大显示项数
     keep-focus - 是否保持当前焦点位置"
  (declare (ignore print-spec max-display-items keep-focus))
  (apply #'lem-if:popup-menu-update (implementation) popup-menu items args))

(defun popup-menu-quit (popup-menu)
  "关闭弹出菜单。
   
   参数:
     popup-menu - 要关闭的菜单对象"
  (lem-if:popup-menu-quit (implementation) popup-menu))

(defun popup-menu-down (popup-menu)
  "移动到菜单下一项。
   
   参数:
     popup-menu - 菜单对象"
  (lem-if:popup-menu-down (implementation) popup-menu))

(defun popup-menu-up (popup-menu)
  "移动到菜单上一项。
   
   参数:
     popup-menu - 菜单对象"
  (lem-if:popup-menu-up (implementation) popup-menu))

(defun popup-menu-first (popup-menu)
  "移动到菜单第一项。
   
   参数:
     popup-menu - 菜单对象"
  (lem-if:popup-menu-first (implementation) popup-menu))

(defun popup-menu-last (popup-menu)
  "移动到菜单最后一项。
   
   参数:
     popup-menu - 菜单对象"
  (lem-if:popup-menu-last (implementation) popup-menu))

(defun popup-menu-select (popup-menu)
  "选择当前菜单项。
   
   参数:
     popup-menu - 菜单对象
   
   效果:
     调用菜单的 action-callback 函数，传入当前选中项"
  (lem-if:popup-menu-select (implementation) popup-menu))
