;;;; utils.lisp - LSP 工具函数
;;;;
;;;; 本文件提供了 LSP 协议相关的工具函数，主要用于：
;;;; 1. 文件路径与 URI 之间的转换
;;;; 2. Lem 编辑器位置与 LSP Position 之间的转换
;;;; 3. Lem 编辑器范围与 LSP Range 之间的转换
;;;;
;;;; LSP 使用基于 0 的行号和列号，而 Lem 使用基于 1 的行号。
;;;;
;;;; 相关文件：
;;;; - type.lisp: LSP 类型系统定义
;;;; - converter.lisp: JSON 与协议对象转换

(defpackage :lem-lsp-base/utils
  (:use :cl)
  (:import-from :quri)
  (:export :pathname-to-uri
           :uri-to-pathname
           :point-lsp-line-number
           :point-to-lsp-position
           :points-to-lsp-range
           :move-to-lsp-position
           :destructuring-lsp-range))
(in-package :lem-lsp-base/utils)

;;; ============================================================================
;;; URI 转换函数
;;; ============================================================================

;; pathname-to-uri - 将文件路径转换为 LSP URI
;; 参数: pathname - 文件路径
;; 返回: file:// 格式的 URI 字符串
(defun pathname-to-uri (pathname)
  (format nil "file://~A" (namestring pathname)))

;; uri-to-pathname - 将 LSP URI 转换为文件路径
;; 参数: uri - URI 字符串
;; 返回: 对应的文件路径
(defun uri-to-pathname (uri)
  (pathname (quri:uri-path (quri:uri uri))))

;;; ============================================================================
;;; 位置转换函数
;;; ============================================================================

;; point-lsp-line-number - 获取点对应的 LSP 行号
;; 参数: point - Lem 点对象
;; 返回: 基于 0 的行号（Lem 行号减 1）
(defun point-lsp-line-number (point)
  (1- (lem:line-number-at-point point)))

;; point-to-lsp-position - 将 Lem 点转换为 LSP Position 对象
;; 参数: point - Lem 点对象
;; 返回: lsp:position 实例，包含 line 和 character 属性
(defun point-to-lsp-position (point)
  (make-instance 'lsp:position
                 :line (point-lsp-line-number point)
                 :character (lem:point-charpos point)))

;; points-to-lsp-range - 将两个 Lem 点转换为 LSP Range 对象
;; 参数: start - 起始点
;;       end - 结束点
;; 返回: lsp:range 实例，包含 start 和 end 位置
(defun points-to-lsp-range (start end)
  (make-instance 'lsp:range
                 :start (point-to-lsp-position start)
                 :end (point-to-lsp-position end)))

;; move-to-lsp-position - 将点移动到 LSP Position 指定的位置
;; 参数: point - 要移动的点对象
;;       position - LSP Position 对象
;; 返回: 移动后的点对象
(defun move-to-lsp-position (point position)
  (check-type point lem:point)
  (check-type position lsp:position)
  (let ((line (lsp:position-line position))
        (character (lsp:position-character position)))
    (lem:move-to-line point (1+ line))
    (lem:character-offset (lem:line-start point) character)
    point))

;; destructuring-lsp-range - 将 LSP Range 解构到两个点
;; 参数: start - 起始点（会被修改）
;;       end - 结束点（会被修改）
;;       range - LSP Range 对象
;; 副作用: 修改 start 和 end 点到 Range 的起始和结束位置
(defun destructuring-lsp-range (start end range)
  (move-to-lsp-position start (lsp:range-start range))
  (move-to-lsp-position end (lsp:range-end range))
  (values))
