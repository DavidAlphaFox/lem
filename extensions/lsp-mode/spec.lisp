;;;; spec.lisp - LSP 语言规范定义
;;;;
;;;; 本文件定义了 LSP 语言服务器的配置规范。
;;;; 每种编程语言需要一个规范来描述如何启动和配置对应的语言服务器。
;;;;
;;;; 主要功能：
;;;; 1. spec 类：定义语言服务器的配置属性
;;;; 2. 语言规范注册和查找
;;;; 3. 动态命令生成（支持根据参数生成命令）
;;;;
;;;; 使用 define-language-spec 宏在 lsp-mode.lisp 中定义语言规范。
;;;;
;;;; 相关文件：
;;;; - lsp-mode.lisp: 使用规范启动 LSP 客户端
;;;; - */lsp-config.lisp: 各语言模式的 LSP 配置

(defpackage :lem-lsp-mode/spec
  (:use :cl)
  (:export :spec-language-id
           :spec-root-uri-patterns
           :spec-command
           :spec-install-command
           :spec-readme-url
           :spec-connection-mode
           :spec-port
           :get-language-spec
           :register-language-spec
           :get-spec-command
           :spec-mode))
(in-package :lem-lsp-mode/spec)

;;; ============================================================================
;;; 语言规范类
;;; ============================================================================

;; spec - LSP 语言服务器配置规范
;; 定义如何连接特定语言的 LSP 服务器
(defclass spec ()
  ((language-id
    :initarg :language-id
    :initform (alexandria:required-argument :language-id)
    :reader spec-language-id
    :documentation "语言标识符，如 \"python\"、\"javascript\"")
   (root-uri-patterns
    :initarg :root-uri-patterns
    :initform nil
    :reader spec-root-uri-patterns
    :documentation "项目根目录标识文件列表，如 (\"package.json\" \"tsconfig.json\")")
   (command
    :initarg :command
    :initform nil
    :reader spec-command
    :documentation "启动语言服务器的命令列表或函数")
   (install-command
    :initarg :install-command
    :initform nil
    :reader spec-install-command
    :documentation "安装语言服务器的命令")
   (readme-url
    :initarg :readme-url
    :initform nil
    :reader spec-readme-url
    :documentation "语言服务器文档 URL")
   (connection-mode
    :initarg :connection-mode
    :initform (alexandria:required-argument :connection-mode)
    :reader spec-connection-mode
    :documentation "连接模式：:stdio 或 :tcp")
   (port
    :initarg :port
    :initform nil
    :reader spec-port
    :documentation "TCP 端口号（仅 :tcp 模式）")
   (mode
    :initarg :mode
    :reader spec-mode
    :documentation "关联的 Lem 主模式")))

;;; ============================================================================
;;; 规范注册和查找
;;; ============================================================================

;; get-language-spec - 获取主模式关联的语言规范
;; 参数: major-mode - 主模式符号
;; 返回: spec 实例
(defun get-language-spec (major-mode)
  (let ((spec (get major-mode 'spec)))
    (assert (typep spec 'spec))
    spec))

;; register-language-spec - 注册语言规范到主模式
;; 参数: major-mode - 主模式符号
;;       spec - 规范实例
(defun register-language-spec (major-mode spec)
  (check-type spec spec)
  (setf (get major-mode 'spec) spec))

;;; ============================================================================
;;; 命令访问
;;; ============================================================================

;; (setf spec-command) - 动态设置命令
;; 允许在运行时修改语言服务器命令
(defmethod (setf spec-command) ((command list)
                                (spec spec))
  (setf (slot-value spec 'command) command))

;; get-spec-command - 获取启动命令
;; 参数: spec - 语言规范
;;       args - 可选参数（传递给命令函数）
;; 返回: 命令列表
;; 如果 command 是函数，则调用该函数并返回结果
(defun get-spec-command (spec &rest args)
  (let ((command (spec-command spec)))
    (if (functionp command)
        (apply command args)
        command)))
