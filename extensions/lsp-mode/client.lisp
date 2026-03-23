;;;; client.lisp - LSP 客户端抽象
;;;;
;;;; 本文件定义了 LSP 客户端的抽象层，支持不同的连接方式。
;;;;
;;;; 主要功能：
;;;; 1. tcp-client: 通过 TCP 套接字连接语言服务器
;;;; 2. stdio-client: 通过标准输入/输出连接语言服务器
;;;;
;;;; 连接方式选择：
;;;; - :stdio - 大多数语言服务器使用此方式，简单可靠
;;;; - :tcp - 某些语言服务器需要 TCP 连接（如调试场景）
;;;;
;;;; 相关文件：
;;;; - lsp-mode.lisp: 使用客户端与语言服务器通信
;;;; - lem-stdio-transport.lisp: STDIO 传输实现
;;;; - async-process-stream.lisp: 异步进程流

(defpackage :lem-lsp-mode/client
  (:use :cl)
  (:import-from :jsonrpc)
  (:import-from :lem-lsp-mode/lem-stdio-transport
                :lem-stdio-transport)
  (:export :dispose
           :tcp-client
           :stdio-client)
  #+sbcl
  (:lock t))
(in-package :lem-lsp-mode/client)

;;; ============================================================================
;;; 客户端协议
;;; ============================================================================

;; dispose - 释放客户端资源
;; 参数: client - 客户端实例
;; 关闭连接并清理相关资源
(defgeneric dispose (client))

;;; ============================================================================
;;; TCP 客户端
;;; ============================================================================

;; tcp-client - 通过 TCP 连接的 LSP 客户端
;; 适用于需要 TCP 连接的语言服务器
(defclass tcp-client (lem-language-client/client:client)
  ((port
    :initarg :port
    :reader tcp-client-port
    :documentation "TCP 端口号")
   (process
    :initform nil
    :initarg :process
    :reader tcp-client-process
    :documentation "语言服务器进程")))

;; jsonrpc-connect - 建立 TCP 连接
(defmethod lem-language-client/client:jsonrpc-connect ((client tcp-client))
  (jsonrpc:client-connect (lem-language-client/client:client-connection client)
                          :mode :tcp
                          :port (tcp-client-port client)))

;; dispose - 关闭 TCP 客户端
;; 终止语言服务器进程
(defmethod dispose ((client tcp-client))
  (when (tcp-client-process client)
    (lem-process:delete-process (tcp-client-process client))))

;;; ============================================================================
;;; STDIO 客户端
;;; ============================================================================

;; stdio-client - 通过标准输入/输出连接的 LSP 客户端
;; 最常用的连接方式，适用于大多数语言服务器
(defclass stdio-client (lem-language-client/client:client)
  ((process :initarg :process
            :reader stdio-client-process
            :documentation "语言服务器进程")))

;; jsonrpc-connect - 建立 STDIO 连接
;; 使用自定义的 lem-stdio-transport 进行通信
(defmethod lem-language-client/client:jsonrpc-connect ((client stdio-client))
  (jsonrpc/client:client-connect-using-class (lem-language-client/client:client-connection client)
                                             'lem-stdio-transport
                                             :process (stdio-client-process client)))

;; dispose - 关闭 STDIO 客户端
;; 终止语言服务器进程
(defmethod dispose ((client stdio-client))
  (async-process:delete-process (stdio-client-process client)))
