;;;; event-queue.lisp - Lem 编辑器事件队列
;;;;
;;;; 本文件实现编辑器的事件队列系统，用于线程间通信。
;;;;
;;;; 在 Lem 的多线程架构中：
;;;; - 前端线程（输入线程）接收用户输入，通过 send-event 发送到队列
;;;; - 编辑器线程从队列中接收事件并处理
;;;;
;;;; 事件类型：
;;;; - 键盘/鼠标事件：从前端发送的输入事件
;;;; - 函数调用：可以是函数对象或符号，在编辑器线程中执行
;;;; - :resize：显示大小变化事件
;;;;
;;;; 相关文件：
;;;;   - frontends/ncurses/mainloop.lisp: 发送事件的示例
;;;;   - src/interp.lisp: 接收并处理事件

(in-package :lem-core)

;;; ============================================================================
;;; 全局事件队列
;;; ============================================================================

;; 编辑器主事件队列（线程安全的并发队列）
(defvar *editor-event-queue* (make-concurrent-queue))

;;; ============================================================================
;;; 队列操作函数
;;; ============================================================================

(defun event-queue-length ()
  "返回事件队列中待处理事件的数量。"
  (len *editor-event-queue*))

(defun send-event (obj)
  "向编辑器事件队列发送事件。
   
   参数:
     obj - 事件对象，可以是：
           - 键盘/鼠标事件结构
           - 函数对象（在编辑器线程中调用）
           - 符号（在编辑器线程中调用）
           - :resize（显示大小变化）
   
   此函数是线程安全的，可从前端线程调用。"
  (enqueue *editor-event-queue* obj))

(defun send-abort-event (editor-thread force)
  "向编辑器线程发送中断事件。
   
   参数:
     editor-thread - 编辑器主线程对象
     force - 是否强制中断
   
   用于取消正在进行的操作（如长时间运行的命令）。"
  (bt2:interrupt-thread editor-thread
                       (lambda ()
                         (interrupt force))))

(defun receive-event (timeout)
  "从事件队列接收事件。
   
   参数:
     timeout - 超时时间（秒），nil 表示无限等待
   
   返回:
     - 事件对象（如果不是特殊事件）
     - nil（如果队列为空或超时）
   
   特殊事件处理：
     - :resize - 处理显示大小变化，不返回事件
     - 函数/符号 - 直接执行，不返回事件"
  (loop
    (let ((e (dequeue *editor-event-queue*
                      :timeout timeout
                      :timeout-value :timeout)))
      (cond ((null e)
             ;; 队列已关闭
             (return nil))
            ((eql e :timeout)
             ;; 超时
             (assert timeout)
             (return nil))
            ((eql e :resize)
             ;; 处理显示大小变化事件
             ;; 只在队列中没有更多 resize 事件时处理
             (when (>= 1 (event-queue-length))
               (update-on-display-resized)))
            ((or (functionp e) (symbolp e))
             ;; 函数或符号事件：直接执行
             (funcall e))
            (t
             ;; 普通事件：返回给调用者处理
             (return e))))))
