;;;; interp.lisp - Lem 编辑器命令循环和错误处理
;;;;
;;;; 本文件实现 Lem 的核心命令循环，负责：
;;;; - 读取用户输入并执行对应命令
;;;; - 错误处理和中断处理
;;;; - 编辑器退出逻辑
;;;; - 后台任务执行
;;;;
;;;; 命令循环流程:
;;;;   1. 重绘显示 (redraw-display)
;;;;   2. 等待并读取命令 (read-command)
;;;;   3. 执行命令 (call-command)
;;;;   4. 处理错误 (editor-abort, editor-condition)
;;;;   5. 返回步骤 1
;;;;
;;;; 相关文件:
;;;;   - src/command.lisp: 命令查找和执行
;;;;   - src/keymap.lisp: 键绑定查找
;;;;   - src/event-queue.lisp: 事件接收

(in-package :lem-core)

;;; ============================================================================
;;; 全局钩子
;;; ============================================================================

;; 编辑器中断时运行的钩子（如 C-g）
(defvar *editor-abort-hook* '())

;; 编辑器退出时运行的钩子
(defvar *exit-editor-hook* '())

;;; ============================================================================
;;; 错误处理
;;; ============================================================================

(defun bailout (condition)
  "严重错误处理：触发编辑器退出并附带错误报告。"
  (signal 'exit-editor
          :report (with-output-to-string (stream)
                    (princ condition stream)
                    (uiop:print-backtrace
                     :stream stream
                     :condition condition))))

(defun pop-up-backtrace (condition)
  "在弹出窗口中显示错误回溯信息。"
  (let ((o (with-output-to-string (stream)
             (princ condition stream)
             (fresh-line stream)
             (uiop:print-backtrace
              :stream stream
              :count 100))))
    (funcall 'pop-up-typeout-window
             (make-buffer "*EDITOR ERROR*")
             :function (lambda (stream)
                         (format stream "~A" o))
             :erase t)))

(defmacro with-error-handler (() &body body)
  "错误处理包装器。
   捕获错误，显示回溯信息，但继续执行。"
  `(handler-case
       (handler-bind ((error
                        (lambda (condition)
                          (handler-bind ((error #'bailout))
                            (pop-up-backtrace condition)
                            (redraw-display)))))
         ,@body)
     (error ())))

;;; ============================================================================
;;; 交互状态
;;; ============================================================================

;; 是否处于交互模式
(defvar *interactive-p* nil)

(defun interactive-p ()
  "返回当前是否处于交互模式。"
  *interactive-p*)

;;; ============================================================================
;;; 继续标志
;;; ============================================================================

;; 上一轮循环的标志
(defvar *last-flags* nil)
;; 当前轮循环的标志
(defvar *curr-flags* nil)

(defmacro save-continue-flags (&body body)
  "保存继续标志状态，用于嵌套命令循环。"
  `(let ((*last-flags* *last-flags*)
         (*curr-flags* *curr-flags*))
     ,@body))

(defun continue-flag (flag)
  "检查并设置继续标志。
   返回标志在上一次循环中的值，并设置当前循环的标志。"
  (prog1 (cdr (assoc flag *last-flags*))
    (push (cons flag t) *last-flags*)
    (push (cons flag t) *curr-flags*)))

(defun nullify-last-flags (flag &rest more-flags)
  "将指定标志在 *LAST-FLAGS* 中设置为 nil。"
  (push (cons flag nil) *last-flags*)
  (when more-flags
    (dotimes (i (length more-flags))
      (push (cons (nth i more-flags) nil) *last-flags*))))

;;; ============================================================================
;;; 命令循环宏
;;; ============================================================================

(defmacro do-command-loop ((&key interactive) &body body)
  "命令循环迭代宏。
   每次迭代重置标志，并设置交互状态。"
  (alexandria:once-only (interactive)
    `(loop :for *last-flags* := nil :then *curr-flags*
           :for *curr-flags* := nil
           :do (let ((*interactive-p* ,interactive)) ,@body))))

;;; ============================================================================
;;; 命令循环实现
;;; ============================================================================

(defun fix-current-buffer-if-broken ()
  "修复当前缓冲区与窗口不匹配的情况。"
  (unless (eq (window-buffer (current-window))
              (current-buffer))
    (setf (current-buffer) (window-buffer (current-window)))))

(defun command-loop-body ()
  "命令循环体：重绘显示，读取并执行命令。"
  (flet ((redraw ()
           "重绘显示（仅当事件队列为空时）"
           (when (= 0 (event-queue-length))
             (without-interrupts
               (handler-bind ((error #'bailout))
                 (redraw-display)))))

         (read-command-and-call ()
           "读取命令并执行"
           (let ((cmd (with-idle-timers ()
                        (read-command))))
             ;; 清除消息（除非是鼠标事件）
             (unless (or (eq cmd '<mouse-motion-event>)
                         (eq cmd '<mouse-event>))
               (message nil))
             (call-command cmd nil)))

         (editor-abort-handler (c)
           "处理编辑器中断（如 C-g）"
           (declare (ignore c))
           (buffer-mark-cancel (current-buffer))
           (run-hooks *editor-abort-hook*))

         (editor-condition-handler (c)
           "处理编辑器条件错误"
           (declare (ignore c))
           (stop-record-key)))

    ;; 重绘显示
    (redraw)

    ;; 处理命令
    (handler-case
        (handler-bind ((editor-abort
                         #'editor-abort-handler)
                       (editor-condition
                         #'editor-condition-handler))
          (let ((*this-command-keys* nil))
            (read-command-and-call)))
      (editor-condition (c)
        (restart-case (error c)
          (lem-restart:message ()
            (let ((message (princ-to-string c)))
              (unless (equal "" message)
                (message "~A" message))))
          (lem-restart:call-function (fn)
            (funcall fn)))))))

;;; ============================================================================
;;; 顶层命令循环
;;; ============================================================================

;; 是否在顶层命令循环
(defvar *toplevel-command-loop-p* t)

(defun toplevel-command-loop-p ()
  "返回是否在顶层命令循环中。"
  *toplevel-command-loop-p*)

;; 命令循环计数器
(defvar *command-loop-counter* 0)

(defun command-loop-counter ()
  "返回命令循环计数器值。"
  *command-loop-counter*)

(defun command-loop ()
  "主命令循环。
   重复执行命令直到编辑器退出。
   在顶层循环中启用完整错误处理。"
  (do-command-loop (:interactive t)
    (incf *command-loop-counter*)
    (if (toplevel-command-loop-p)
        ;; 顶层循环：完整错误处理
        (with-error-handler ()
          (let ((*toplevel-command-loop-p* nil))
            (handler-bind ((editor-condition
                             (lambda (c)
                               (declare (ignore c))
                               (invoke-restart 'lem-restart:message))))
              (command-loop-body))))
        ;; 嵌套循环：简单处理
        (command-loop-body))
    (fix-current-buffer-if-broken)))

(defun toplevel-command-loop (initialize-function)
  "顶层命令循环入口。
   初始化编辑器状态，然后进入命令循环。
   处理 exit-editor 条件以正常退出。"
  (handler-bind ((exit-editor
                   (lambda (c)
                     (return-from toplevel-command-loop
                       (exit-editor-report c)))))
    (with-error-handler ()
      (funcall initialize-function))
    (with-editor-stream ()
      (command-loop))))

;;; ============================================================================
;;; 编辑器退出
;;; ============================================================================

(defun exit-editor (&optional report)
  "退出编辑器。
   1. 运行退出钩子
   2. 禁用所有全局次模式
   3. 触发 exit-editor 条件"
  (run-hooks *exit-editor-hook*)
  (mapc #'disable-minor-mode (active-global-minor-modes))
  (signal 'exit-editor :report report))

;;; ============================================================================
;;; 后台任务
;;; ============================================================================

(defun call-background-job (function cont)
  "在后台线程中执行任务。
   
   参数:
     function - 要执行的任务函数
     cont - 完成后的续延函数（接收任务结果）
   
   成功时：在编辑器线程中调用 (funcall cont result)
   失败时：显示错误缓冲区"
  (bt2:make-thread
   (lambda ()
     (let ((error-text))
       (handler-case
           (handler-bind ((error (lambda (c)
                                   (setf error-text
                                         (with-output-to-string (stream)
                                           (princ c stream)
                                           (fresh-line stream)
                                           (uiop:print-backtrace
                                            :stream stream
                                            :count 100))))))
             (let ((result (funcall function)))
               ;; 通过事件队列将结果发送回编辑器线程
               (send-event (lambda () (funcall cont result))))))
         (error ()
           ;; 在编辑器线程中显示错误
           (send-event (lambda ()
                         (let ((buffer (make-buffer "*BACKGROUND JOB ERROR*")))
                           (erase-buffer buffer)
                           (insert-string (buffer-point buffer)
                                          error-text)
                           (pop-to-buffer buffer)
                           (buffer-start (buffer-point buffer)))))))))))
