;;;; yason-utils.lisp - JSON 解析工具
;;;;
;;;; 本文件提供了 Yason JSON 库的配置和工具函数。
;;;; LSP 协议使用 JSON 作为消息格式，需要正确配置 JSON 解析行为。
;;;;
;;;; 主要功能：
;;;; 1. 配置 Yason 将 JSON null 解析为 :null 关键字
;;;; 2. 配置 Yason 将 JSON 数组解析为向量
;;;; 3. 提供线程安全的 JSON 解析环境
;;;;
;;;; 相关文件：
;;;; - converter.lisp: 使用这些配置进行 JSON 转换
;;;; - type.lisp: 定义了 +null+ 常量

(defpackage :lem-lsp-base/yason-utils
  (:use :cl)
  (:export :with-yason-bindings
           :parse-json))
(in-package :lem-lsp-base/yason-utils)

;;; ============================================================================
;;; Yason 配置
;;; ============================================================================

;; *yason-bindings* - Yason 解析配置的动态绑定列表
;; 这些配置确保 JSON 与 LSP 类型系统正确对应：
;; - null -> :null （而非 nil）
;; - 数组 -> vector （而非 list）
(defparameter *yason-bindings*
  '((yason:*parse-json-null-as-keyword* . t)
    (yason:*parse-json-arrays-as-vectors* . t)
    (jsonrpc/yason:*parse-json-null-as-keyword* . t)
    (jsonrpc/yason:*parse-json-arrays-as-vectors* . t)))

;;; ============================================================================
;;; 配置宏和函数
;;; ============================================================================

;; with-yason-bindings - 在配置环境中执行代码
;; 确保所有 JSON 解析使用正确的 LSP 配置
;; 用法: (with-yason-bindings () (yason:parse ...))
(defmacro with-yason-bindings (() &body body)
  `(call-with-yason-bindings (lambda () ,@body)))

;; call-with-yason-bindings - 配置环境的函数版本
;; 设置线程默认绑定并应用 Yason 配置
(defun call-with-yason-bindings (function)
  (let ((bt2:*default-special-bindings*
          (append *yason-bindings*
                  bt2:*default-special-bindings*)))
    (progv (mapcar #'car *yason-bindings*)
        (mapcar #'cdr *yason-bindings*)
      (funcall function))))

;; parse-json - 在正确配置下解析 JSON
;; 参数: input - JSON 字符串或流
;; 返回: 解析后的 Lisp 数据结构
(defun parse-json (input)
  (with-yason-bindings ()
    (yason:parse input)))
