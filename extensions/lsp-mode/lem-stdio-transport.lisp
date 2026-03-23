;;;; lem-stdio-transport.lisp - LSP STDIO 传输层
;;;;
;;;; 本文件实现了通过标准输入/输出与语言服务器通信的传输层。
;;;; 这是 LSP 最常用的通信方式，大多数语言服务器都支持。
;;;;
;;;; 主要功能：
;;;; 1. lem-stdio-transport 类：实现 jsonrpc 传输协议
;;;; 2. 消息发送：使用 Content-Length 头格式发送 JSON-RPC 消息
;;;; 3. 消息接收：从异步进程流读取并解析响应
;;;;
;;;; JSON-RPC 消息格式：
;;;; Content-Length: <字节数>\r\n
;;;; \r\n
;;;; <JSON 内容>
;;;;
;;;; 相关文件：
;;;; - async-process-stream.lisp: 异步进程流实现
;;;; - client.lisp: 客户端使用此传输层

(defpackage :lem-lsp-mode/lem-stdio-transport
  (:use :cl
        :jsonrpc/transport/interface)
  (:import-from :jsonrpc/connection
                :connection)
  (:import-from :jsonrpc/request-response
                :parse-message)
  (:import-from :lem-lsp-mode/async-process-stream
                :make-input-stream)
  (:export :lem-stdio-transport))
(in-package :lem-lsp-mode/lem-stdio-transport)

;;; ============================================================================
;;; STDIO 传输类
;;; ============================================================================

;; lem-stdio-transport - STDIO 传输实现
;; 通过进程的标准输入/输出进行 JSON-RPC 通信
(defclass lem-stdio-transport (transport)
  ((process :initarg :process
            :reader lem-stdio-transport-process
            :documentation "语言服务器进程")
   (stream :initarg :stream
           :initform nil
           :accessor lem-stdio-transport-stream
            :documentation "输入流（用于读取进程输出）")))

;; initialize-instance - 初始化传输实例
;; 自动创建输入流包装器
(defmethod initialize-instance ((instance lem-stdio-transport) &rest initargs)
  (declare (ignore initargs))
  (let ((instance (call-next-method)))
    (unless (lem-stdio-transport-stream instance)
      (setf (lem-stdio-transport-stream instance)
            (make-input-stream (lem-stdio-transport-process instance))))
    instance))

;;; ============================================================================
;;; 客户端启动
;;; ============================================================================

;; start-client - 启动客户端连接
;; 创建两个后台线程：
;; 1. processing 线程：处理接收到的消息
;; 2. reading 线程：从进程输出读取数据
(defmethod start-client ((transport lem-stdio-transport))
  (let ((connection (make-instance 'connection
                                    :request-callback (transport-message-callback transport))))
    (setf (transport-connection transport) connection)
    (setf (transport-threads transport)
          (list
           (bt2:make-thread
            (lambda ()
              (run-processing-loop transport connection))
            :name "lem-lsp-mode/lem-stdio-transport processing")
           (bt2:make-thread
            (lambda ()
              (run-reading-loop transport connection))
            :name "lem-lsp-mode/lem-stdio-transport reading")))
    connection))

;;; ============================================================================
;;; 消息发送和接收
;;; ============================================================================

;; send-message-using-transport - 发送消息到语言服务器
;; 使用 Content-Length 头格式发送 JSON-RPC 消息
;; 格式: "Content-Length: <长度>\r\n\r\n<JSON>"
(defmethod send-message-using-transport ((transport lem-stdio-transport) connection message)
  (let* ((json (with-output-to-string (s)
                 (yason:encode message s)))
         (body (format nil
                       "Content-Length: ~A~C~C~:*~:*~C~C~A"
                       (babel:string-size-in-octets json)
                       #\Return
                       #\Newline
                       json)))
    (async-process:process-send-input
     (lem-stdio-transport-process transport)
     body)))

;; receive-message-using-transport - 从语言服务器接收消息
;; 读取 HTTP 头获取内容长度，然后解析 JSON 消息
(defmethod receive-message-using-transport ((transport lem-stdio-transport) connection)
  (let* ((stream (lem-stdio-transport-stream transport))
         (headers (handler-case (read-headers stream)
                    (error ()
                      ;; 进程结束时 read-headers 会出错，在此处理
                      (return-from receive-message-using-transport nil))))
         (length (ignore-errors (parse-integer (gethash "content-length" headers)))))
    (when length
      (jsonrpc:parse-message stream))))

;;; ============================================================================
;;; 辅助函数
;;; ============================================================================

;; read-headers - 读取 HTTP 头
;; 从流中读取直到空行，返回头信息的哈希表
;; 注意：头名转换为小写
(defun read-headers (stream)
  ;; 复制自 jsonrpc/transport/stdio::read-headers
  (let ((headers (make-hash-table :test 'equal)))
    (loop for line = (read-line stream)
          until (equal (string-trim '(#\Return #\Newline) line) "")
          do (let* ((colon-pos (position #\: line))
                    (field (string-downcase (subseq line 0 colon-pos)))
                    (value (string-trim '(#\Return #\Space #\Tab) (subseq line (1+ colon-pos)))))
               (setf (gethash field headers) value)))
    headers))
