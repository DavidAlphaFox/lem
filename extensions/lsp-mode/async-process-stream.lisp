;;;; async-process-stream.lisp - 异步进程输入流
;;;;
;;;; 本文件实现了从异步进程读取输出的流包装器。
;;;; 用于从语言服务器进程的标准输出中读取 JSON-RPC 消息。
;;;;
;;;; 主要功能：
;;;; 1. input-stream 类：包装异步进程，提供流式读取接口
;;;; 2. 实现 trivial-gray-streams 协议，支持标准流操作
;;;; 3. 缓冲区管理：累积进程输出，按需读取
;;;;
;;;; 相关文件：
;;;; - lem-stdio-transport.lisp: 使用此类进行 STDIO 通信
;;;; - client.lisp: 创建客户端时使用

(defpackage :lem-lsp-mode/async-process-stream
  (:use :cl
        :trivial-gray-streams)
  (:export :make-input-stream))
(in-package :lem-lsp-mode/async-process-stream)

;;; ============================================================================
;;; 输入流类
;;; ============================================================================

;; input-stream - 异步进程的字符输入流
;; 实现标准流协议，允许从异步进程逐字符读取
(defclass input-stream (fundamental-character-input-stream)
  ((process :initarg :process
            :reader input-stream-process
            :documentation "异步进程对象")
   (buffer-string :initform ""
                  :accessor input-stream-buffer-string
                  :documentation "接收缓冲区")
   (position :initform 0
             :accessor input-stream-position
             :documentation "当前读取位置")
   (logger :initform nil
           :initarg :logger
           :reader input-stream-logger
           :documentation "可选日志函数")))

;; make-input-stream - 创建异步进程输入流
;; 参数: process - 异步进程对象
;;       :logger - 可选的日志函数
;; 返回: input-stream 实例
(defun make-input-stream (process &key logger)
  (make-instance 'input-stream :process process :logger logger))

;;; ============================================================================
;;; 流操作实现
;;; ============================================================================

;; receive-output-if-necessary - 在需要时接收进程输出
;; 当缓冲区耗尽时，从进程接收新数据
(defun receive-output-if-necessary (stream)
  (when (<= (length (input-stream-buffer-string stream))
            (input-stream-position stream))
    (let ((output (async-process:process-receive-output (input-stream-process stream))))
      (setf (input-stream-buffer-string stream) output)
      (when (input-stream-logger stream)
        (funcall (input-stream-logger stream) output)))
    (setf (input-stream-position stream)
          0)))

;; ahead-char - 获取当前位置的字符（不移动位置）
(defun ahead-char (stream)
  (char (input-stream-buffer-string stream)
        (input-stream-position stream)))

;; stream-read-char - 读取一个字符
;; 实现 trivial-gray-streams 协议
(defmethod stream-read-char ((stream input-stream))
  (receive-output-if-necessary stream)
  (prog1 (ahead-char stream)
    (incf (input-stream-position stream))))

;; stream-unread-char - 回退一个字符
;; 实现 trivial-gray-streams 协议
(defmethod stream-unread-char ((stream input-stream) character)
  (decf (input-stream-position stream))
  nil)

#|(注释掉的实现)
(defmethod stream-read-char-no-hang ((stream input-stream))
  )
|#

;; stream-peek-char - 查看下一个字符（不消耗）
;; 实现 trivial-gray-streams 协议
(defmethod stream-peek-char ((stream input-stream))
  ;; TODO: 进程结束时返回 :EOF?
  (receive-output-if-necessary stream)
  (ahead-char stream))

;; stream-listen - 检查是否有数据可读
;; 始终返回 T，因为进程总是可能有输出
(defmethod stream-listen ((stream input-stream))
  t)

#|(注释掉的实现)
(defmethod stream-read-line ((stream input-stream))
  (receive-output-if-necessary stream)
  (let ((pos (position #\newline
                       (input-stream-buffer-string stream)
                       :start (input-stream-position stream))))
    (prog1 (subseq (input-stream-buffer-string stream)
                   (input-stream-position stream)
                   pos)
      (setf (input-stream-position stream)
            (or (if pos
                    (1+ pos)
                    (length (input-stream-buffer-string stream))))))))
|#

;; stream-clear-input - 清除输入缓冲区
(defmethod stream-clear-input ((stream input-stream))
  nil)
