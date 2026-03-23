;;;; lem.lisp - Lem 编辑器主入口点
;;;;
;;;; 本文件是 Lem 编辑器的核心启动模块，负责：
;;;; - 解析命令行参数
;;;; - 选择并初始化前端实现
;;;; - 启动编辑器线程
;;;; - 加载用户配置文件
;;;;
;;;; 启动流程: main → lem → launch → invoke-frontend → run-editor-thread
;;;;
;;;; 相关文件:
;;;;   - interface.lisp: 前端抽象层
;;;;   - interp.lisp: 命令循环
;;;;   - config.lisp: 配置系统

(in-package :lem-core)

;;; ============================================================================
;;; 全局钩子变量
;;; ============================================================================

;; 位置设置钩子，用于记录缓冲区位置历史
(defvar *set-location-hook* '((push-buffer-point . 0)))

;; 初始化前钩子，在加载配置文件之前执行
(defvar *before-init-hook* '())

;; 初始化后钩子，在加载配置文件之后执行
(defvar *after-init-hook* '())

;; 启动画面函数，可自定义启动时显示的内容
(defvar *splash-function* nil)

;;; ============================================================================
;;; 编辑器状态
;;; ============================================================================

;; 标记是否在编辑器环境中运行（用于检测嵌套调用）
(defvar *in-the-editor* nil)

;;; ============================================================================
;;; 帧初始化
;;; ============================================================================

(defun setup-first-frame ()
  "创建并设置第一个编辑器帧。
   帧(Frame)是编辑器的顶层容器，包含窗口树和显示区域。
   此函数创建帧、映射到前端实现，并使用原始缓冲区初始化。"
  (let ((frame (make-frame nil)))
    (map-frame (implementation) frame)
    (setup-frame frame (primordial-buffer))))

;;; ============================================================================
;;; 定时器管理
;;; ============================================================================

;; Lem 定时器管理器类，继承自基础定时器管理器
(defclass lem-timer-manager (timer-manager) ())

(defmethod send-timer-notification ((lem-timer-manager timer-manager) continue)
  "定时器通知回调：通过事件队列发送定时器事件到编辑器线程。
   CONTINUE 是定时器到期后要执行的续延函数。"
  (send-event (lambda ()
                (funcall continue)
                (redraw-display))))

;;; ============================================================================
;;; 编辑器初始化
;;; ============================================================================

(let ((once nil))
  (defun setup ()
    "初始化编辑器核心组件。
     - 设置第一个帧
     - 初始化语法扫描器（仅一次）
     - 注册文件处理钩子
     - 注册输入事件钩子"
    (setup-first-frame)
    (unless once
      (setf once t)
      (init-syntax-scanner)
      (add-hook *find-file-hook* 'process-file 5000)
      (add-hook (variable-value 'before-save-hook :global) 'process-file)
      (add-hook *input-hook*
                (lambda (event)
                  (push event *this-command-keys*))))))

(defun teardown ()
  "清理编辑器资源，销毁所有帧。"
  (teardown-frames))

;;; ============================================================================
;;; 配置文件加载
;;; ============================================================================

(defun load-init-file ()
  "加载用户初始化文件。
   按优先级搜索配置文件：
     1. $LEM_HOME/init.lisp
     2. ~/.lemrc
     3. 当前目录/.lemrc（如果不在家目录）
   
   配置文件在 :lem-user 包中执行，避免污染核心包。"
  (flet ((maybe-load (path)
           "尝试加载指定路径的文件，成功返回 T"
           (when (probe-file path)
             (load path)
             (message "Load file: ~a" path)
             t)))
    (let ((home (user-homedir-pathname))
          (current-dir (probe-file "."))
          (*package* (find-package :lem-user)))
      (or (maybe-load (merge-pathnames "init.lisp" (lem-home)))
          (maybe-load (merge-pathnames ".lemrc" home)))
      (unless (uiop:pathname-equal current-dir (user-homedir-pathname))
        (maybe-load (merge-pathnames ".lemrc" current-dir))))))

;;; ============================================================================
;;; ASDF 源注册表初始化
;;; ============================================================================

(defun initialize-source-registry ()
  "初始化 ASDF 源注册表，添加 Lem 源码目录。
   排除 .qlot 目录以避免依赖冲突。"
  (asdf:initialize-source-registry
   `(:source-registry
     :inherit-configuration
     (:also-exclude ".qlot")
     (:tree ,(asdf:system-source-directory :lem)))))

(defun init-at-build-time ()
  "构建时初始化函数。
   当 Lem 可执行文件构建时调用此函数。
   如果存在 $HOME/.lem/build-init.lisp 文件则加载它。
   
   与 init.lisp 的区别：
   - init.lisp: 编辑器启动时加载
   - build-init.lisp: 二进制文件创建时加载
   
   参见: scripts/build-ncurses.lisp, scripts/build-sdl2.lisp"
  (initialize-source-registry)
  (let ((file (merge-pathnames "build-init.lisp" (lem-home))))
    (when (uiop:file-exists-p file)
      (load file))))

;;; ============================================================================
;;; 编辑器生命周期
;;; ============================================================================

(defun init (args)
  "初始化编辑器状态。
   1. 运行 *before-init-hook* 钩子
   2. 加载用户配置文件（除非指定了 --without-init-file）
   3. 运行 *after-init-hook* 钩子
   4. 应用命令行参数"
  (run-hooks *before-init-hook*)
  (unless (command-line-arguments-without-init-file args)
    (load-init-file))
  (run-hooks *after-init-hook*)
  (apply-args args))

(defun run-editor-thread (initialize args finalize)
  "在独立线程中运行编辑器主循环。
   INITIALIZE: 前端初始化函数（可选）
   ARGS: 命令行参数
   FINALIZE: 退出时的清理函数（可选）
   
   线程流程:
   1. 调用前端初始化函数
   2. 设置编辑器流和定时器管理器
   3. 设置 *in-the-editor* 标志
   4. 调用 setup() 初始化帧
   5. 进入顶层命令循环
   6. 退出时调用清理函数"
  (bt2:make-thread
   (lambda ()
     (when initialize (funcall initialize))
     (unwind-protect
          (let (#+lispworks (lw:*default-character-element-type* 'character))
            (with-editor-stream ()
              (with-timer-manager (make-instance 'lem-timer-manager)
                (setf *in-the-editor* t)
                (setup)
                (let ((report (toplevel-command-loop (lambda () (init args)))))
                  (when finalize (funcall finalize report))
                  (teardown)))))
       (setf *in-the-editor* nil)))
   :name "editor"))

(defun find-editor-thread ()
  "查找并返回编辑器主线程对象。"
  (find "editor" (bt2:all-threads)
        :test #'equal
        :key #'bt2:thread-name))

;;; ============================================================================
;;; 版本信息
;;; ============================================================================

;; 版本字符串，在编译时确定（通过 get-version-string 函数获取）
(defvar *version* (get-version-string))

;;; ============================================================================
;;; 启动入口点
;;; ============================================================================

(defun launch (args)
  "启动 Lem 编辑器的主函数。
   
   参数 ARGS 必须是 command-line-arguments 结构体。
   
   启动流程:
   1. 检查 --help 参数，显示帮助并退出
   2. 检查 --version 参数，显示版本并退出
   3. 配置日志系统
   4. 如果已在编辑器中，直接应用参数
   5. 否则获取默认前端实现并启动
   
   对于 SBCL: 设置默认文件编码为 UTF-8"
  (check-type args command-line-arguments)
  ;; 对于 SBCL，设置默认文件编码为 UTF-8
  ;; （在 Windows 上默认由代码页决定，如 :cp932）
  #+sbcl
  (setf sb-impl::*default-external-format* :utf-8)
  
  ;; 配置日志系统
  (cond
    ((command-line-arguments-log-filename args)
     (apply #'log:config
            :sane
            :daily (command-line-arguments-log-filename args)
            (list
             (if (command-line-arguments-debug args)
                 :debug
                 :info))))
    (t
     (log:config :sane :daily (merge-pathnames "debug.log" (lem-home)) :info)))
  
  ;; 处理 --help 参数
  (when (command-line-arguments-help args)
    (show-help)
    (return-from launch))
  
  ;; 处理 --version 参数
  (when (command-line-arguments-version args)
    (uiop:println *version*)
    (return-from launch))
  
  (log:info "Starting Lem")
  
  ;; 启动编辑器
  (cond (*in-the-editor*
         ;; 已在编辑器中，直接应用参数
         (apply-args args))
        (t
         ;; 获取默认前端实现并启动
         (let ((implementation (get-default-implementation
                                :implementation (command-line-arguments-interface args))))
           (unless implementation
             (error "implementation ~A not found" implementation-keyword))
           
           (invoke-frontend
            (lambda (&optional initialize finalize)
              (run-editor-thread initialize args finalize))
            :implementation implementation)))))

(defun lem (&rest args)
  "Lem 编辑器的编程接口入口点。
   接受命令行参数字符串列表，解析后启动编辑器。
   
   示例:
     (lem \"--help\")
     (lem \"file1.lisp\" \"file2.lisp\")
     (lem \"--eval\" \"(+ 1 2)\")"
  (launch (parse-args args)))

(defun main (&optional (args (uiop:command-line-arguments)))
  "Lem 编辑器的命令行入口点。
   作为可执行文件的主函数被调用。
   
   示例命令行:
     lem --help
     lem file.lisp
     lem --eval '(message \"Hello\")'"
  (apply #'lem args))

;;; ============================================================================
;;; SBCL 集成
;;; ============================================================================

;; 注册 SBCL 的 *ed-functions*，使得 (ed) 函数调用 Lem
;; 这样可以在 REPL 中使用 (ed "file.lisp") 打开文件
#+sbcl
(push #'(lambda (x)
          (if x
              (lem x)
              (lem))
          t)
      sb-ext:*ed-functions*)

;;; ============================================================================
;;; 编辑器警告处理
;;; ============================================================================

;; 在初始化后检查是否有警告需要显示
(add-hook *after-init-hook*
          (lambda ()
            "初始化后显示编辑器警告（如果有）。
             警告信息收集在 *editor-warnings* 中，
             在此创建 *EDITOR WARNINGS* 缓冲区显示所有警告。"
            (when *editor-warnings*
              (let ((buffer (make-buffer "*EDITOR WARNINGS*")))
                (dolist (warning *editor-warnings*)
                  (insert-string (buffer-point buffer) warning)
                  (insert-character (buffer-point buffer) #\newline))
                (pop-to-buffer buffer)))))
