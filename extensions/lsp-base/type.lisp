;;;; type.lisp - LSP 类型系统
;;;;
;;;; 本文件实现了 Language Server Protocol (LSP) 的类型系统。
;;;; LSP 是编辑器与语言服务器之间通信的标准化协议。
;;;;
;;;; 主要功能：
;;;; 1. LSP 基本类型定义（URI、整数、字符串、布尔值、数组、映射等）
;;;; 2. 协议对象元类（protocol-class）用于定义 LSP 消息类型
;;;; 3. 请求消息和通知消息的基类
;;;; 4. 类型转换工具函数（Lisp 命名与 JSON PascalCase 互转）
;;;;
;;;; 相关文件：
;;;; - converter.lisp: JSON 与协议对象之间的转换
;;;; - utils.lisp: LSP 位置和范围工具函数
;;;; - protocol-3-17.lisp: LSP 3.17 协议的具体类型定义

(defpackage :lem-lsp-base/type
  (:use :cl)
  (:export :+null+
           :+true+
           :+false+
           :json-type-error
           :required-argument-error
           :lsp-uri
           :lsp-document-uri
           :lsp-integer
           :lsp-uinteger
           :lsp-decimal
           :lsp-regexp
           :lsp-string
           :lsp-boolean
           :lsp-null
           :lsp-array
           :lsp-map
           :lsp-tuple
           :lsp-interface
           :protocol-object
           :protocol-class
           :define-enum
           :define-type-alias
           :define-class
           :request-message
           :request-message-deprecated
           :request-message-documentation
           :request-message-error-data
           :request-message-message-direction
           :request-message-method
           :request-message-params
           :request-message-partial-result
           :request-message-proposed
           :request-message-registration-method
           :request-message-registration-options
           :request-message-result
           :request-message-since
           :notification-message
           :notification-message-deprecated
           :notification-message-documentation
           :notification-message-message-direction
           :notification-message-method
           :notification-message-params
           :notification-message-proposed
           :notification-message-registration-method
           :notification-message-registration-options
           :notification-message-since
           :define-request-message
           :define-notification-message
           :protocol-class-slots
           :pascal-to-lisp-case
           :lisp-to-pascal-case
           :make-lsp-map
           :make-lsp-array
           :get-map
           :lsp-array-p
           :lsp-null-p))
(in-package :lem-lsp-base/type)

;;; ============================================================================
;;; 编译选项
;;; ============================================================================

(declaim (optimize (speed 0) (safety 3) (debug 3)))

;;; ============================================================================
;;; LSP 常量
;;; ============================================================================

;; LSP 协议中 null/true/false 的表示
(defconstant +null+ :null)    ; LSP null 值
(defconstant +true+ t)        ; LSP true 值
(defconstant +false+ nil)     ; LSP false 值

;;; ============================================================================
;;; 错误条件
;;; ============================================================================

;; JSON 类型错误 - 当值不符合预期的 LSP 类型时触发
(define-condition json-type-error ()
  ((type :initarg :type)
   (value :initarg :value)
   (context :initarg :context :initform nil))
  (:report (lambda (c s)
             (with-slots (value type context) c
               (if context
                   (format s "~S is not a ~S in ~S" value type context)
                   (format s "~S is not a ~S" value type))))))

;; 必需参数错误 - 当缺少必需的协议参数时触发
(define-condition required-argument-error (json-type-error)
  ((slot-name :initarg :slot-name)
   (class-name :initarg :class-name))
  (:report (lambda (condition stream)
             (with-slots (slot-name class-name) condition
               (format stream
                       "Required argument ~A missing for ~A."
                       slot-name
                       class-name)))))

;;; ============================================================================
;;; LSP 基本类型定义
;;; ============================================================================

;; LSP URI 类型 - 统一资源标识符
(deftype lsp-uri () 'string)
;; LSP DocumentUri 类型 - 文档 URI
(deftype lsp-document-uri () 'string)
;; LSP integer 类型 - 32 位有符号整数
(deftype lsp-integer () 'integer)
;; LSP uinteger 类型 - 32 位无符号整数
(deftype lsp-uinteger () '(integer 0 *))
;; LSP decimal 类型 - 十进制数
(deftype lsp-decimal () 'integer)
;; LSP RegExp 类型 - 正则表达式字符串
(deftype lsp-regexp () 'string)
;; LSP string 类型 - 可选固定值字符串
(deftype lsp-string (&optional (string nil stringp))
  (if stringp
      (labels ((f (value)
                 (equal value string)))
        (let ((g (gensym)))
          (setf (symbol-function g) #'f)
          `(satisfies ,g)))
      'string))
;; LSP boolean 类型 - 布尔值
(deftype lsp-boolean () 'boolean)
;; LSP null 类型 - 空值
(deftype lsp-null () '(eql :null))

;; LSP array 类型 - 元素数组
(deftype lsp-array (&optional element-type)
  (declare (ignore element-type))
  'vector)

;; LSP map 类型 - 键值对映射
(deftype lsp-map (key value)
  (declare (ignore key value))
  'hash-table)

;; LSP tuple 类型 - 固定类型元组
(deftype lsp-tuple (&rest types)
  (declare (ignore types))
  'vector)

;; LSP interface 类型 - 对象接口
(deftype lsp-interface (properties &key &allow-other-keys)
  (declare (ignore properties))
  'hash-table)

;;; ============================================================================
;;; 协议类元类
;;; ============================================================================

;; protocol-class - 用于 LSP 协议对象的元类
;; 提供协议版本和废弃信息等元数据
(defclass protocol-class (c2mop:standard-class)
  ((deprecated :initarg :deprecated
               :reader protocol-class-deprecated
               :documentation "是否已废弃")
   (proposed :initarg :proposed
             :reader protocol-class-proposed
             :documentation "是否为提议状态")
   (since :initarg :since
          :reader protocol-class-since
          :documentation "引入版本")))

(defmethod c2mop:validate-superclass ((class protocol-class)
                                      (super c2mop:standard-class))
  t)

(defmethod c2mop:validate-superclass ((class c2mop:standard-class)
                                      (super protocol-class))
  t)

;; protocol-slot - 协议对象的槽定义
;; 扩展标准槽定义，添加可选性、废弃信息等
(defclass protocol-slot (c2mop:standard-direct-slot-definition)
  ((optional
    :initarg :optional
    :initform nil
    :reader protocol-slot-optional-p
    :documentation "槽是否可选")
   (deprecated
    :initarg :deprecated
    :initform nil
    :reader protocol-slot-deprecated
    :documentation "槽是否已废弃")
   (proposed
    :initarg :proposed
    :reader protocol-slot-proposed
    :documentation "槽是否为提议状态")
   (since
    :initarg :since
    :reader protocol-slot-since
    :documentation "槽引入版本")))

(defmethod c2mop:direct-slot-definition-class ((class protocol-class) &rest initargs)
  (declare (ignore initargs))
  (find-class 'protocol-slot))

;; protocol-object - 所有 LSP 协议对象的基类
(defclass protocol-object () ()
  (:metaclass protocol-class))

;;; ============================================================================
;;; 协议对象初始化和验证
;;; ============================================================================

;; protocol-class-slots - 获取协议类的所有槽定义
;; 参数: class - 协议类
;; 返回: 槽定义列表
(defun protocol-class-slots (class)
  (unless (c2mop:class-finalized-p class)
    (c2mop:finalize-inheritance class))
  (loop :with base := (find-class 'protocol-class)
        :for superclass :in (c2mop:class-precedence-list class)
        :while (eq base (class-of superclass))
        :append (c2mop:class-direct-slots superclass)))

;; check-argument-is-required - 检查必需参数是否存在
;; 参数: class - 协议类
;;       slot - 槽定义
;; 当必需参数缺失时抛出 required-argument-error
(defun check-argument-is-required (class slot)
  (unless (protocol-slot-optional-p slot)
    (error 'required-argument-error
           :slot-name (c2mop:slot-definition-name slot)
           :class-name (class-name class))))

;; check-initargs - 验证协议对象的所有初始化参数
;; 参数: protocol-object - 要验证的协议对象
;; 检查所有槽的值是否符合声明的类型
(defun check-initargs (protocol-object)
  (loop :with class := (class-of protocol-object)
        :for slot :in (protocol-class-slots class)
        :for slot-name := (c2mop:slot-definition-name slot)
        :do (cond ((slot-boundp protocol-object slot-name)
                   (let ((value (slot-value protocol-object slot-name))
                         (expected-type (c2mop:slot-definition-type slot)))
                     (unless (typep value expected-type)
                       (if (eq value :null)
                           ;; 如果值为 null，视为无参数
                           (check-argument-is-required class slot)
                           (error 'json-type-error
                                  :type expected-type
                                  :value value
                                  :context slot-name)))))
                  (t
                   (check-argument-is-required class slot)))))

;; initialize-instance - 协议对象初始化方法
;; 在创建实例后自动验证参数
(defmethod initialize-instance ((instance protocol-object) &rest initargs &key &allow-other-keys)
  (declare (ignore initargs))
  (let ((instance (call-next-method)))
    (check-initargs instance)
    instance))

;;; ============================================================================
;;; 类型定义宏
;;; ============================================================================

#|(注释掉的替代实现)
(defmacro define-enum (name (&rest fields) &body options)
  (declare (ignore options))
  (alexandria:with-unique-names (f x anon-name)
    (let ((field-values (mapcar #'second fields)))
      `(progn
         (deftype ,name ()
           (labels ((,f (,x) (member ,x ',field-values :test #'equal)))
             (let ((,anon-name (gensym)))
               (setf (symbol-function ,anon-name) #',f)
               `(satisfies ,,anon-name))))
         ,@(loop :for (field-name value) :in fields
                 :for variable := (intern (format nil "~A-~A" name field-name))
                 :collect `(defparameter ,variable ,value))
         ',name))))
|#

;; define-enum - 定义 LSP 枚举类型
;; 参数: name - 枚举名称
;;       fields - 枚举字段列表，每个字段为 (字段名 值)
;;       options - 可选选项
;; 生成类型定义和对应的常量
(defmacro define-enum (name (&rest fields) &body options)
  (declare (ignore options))
  `(progn
     (deftype ,name ()
       t)
     ,@(loop :for (field-name value) :in fields
             :for variable := (intern (format nil "~A-~A" name field-name))
             :collect `(defparameter ,variable ,value))
     ',name))

;; define-type-alias - 定义类型别名
;; 参数: name - 别名名称
;;       type - 目标类型
;;       options - 可选选项（支持 :documentation）
(defmacro define-type-alias (name type &body options)
  (let ((doc (second (assoc :documentation options))))
    `(deftype ,name () ,@(when `(,doc)) ',type)))

;; define-class - 定义协议类
;; 参数: name - 类名
;;       superclasses - 父类列表（默认为 protocol-object）
;;       args - 槽定义和其他类选项
(defmacro define-class (name superclasses &body args)
  `(defclass ,name ,(if (null superclasses)
                        '(protocol-object)
                        superclasses)
     ,@args
     (:metaclass protocol-class)))

;;; ============================================================================
;;; 消息基类
;;; ============================================================================

;; request-message - LSP 请求消息基类
;; 表示客户端与服务器之间的请求/响应消息
(defclass request-message ()
  ((deprecated
    :initarg :deprecated
    :reader request-message-deprecated
    :documentation "是否已废弃")
   (documentation
    :initarg :documentation
    :reader request-message-documentation
    :documentation "消息文档说明")
   (error-data
    :initarg :error-data
    :reader request-message-error-data
    :documentation "错误数据类型")
   (message-direction
    :initarg :message-direction
    :reader request-message-message-direction
    :documentation "消息方向（clientToServer/serverToClient/both）")
   (method
    :initarg :method
    :reader request-message-method
    :documentation "请求方法名")
   (params
    :initarg :params
    :reader request-message-params
    :documentation "请求参数类型")
   (partial-result
    :initarg :partial-result
    :reader request-message-partial-result
    :documentation "部分结果类型")
   (proposed
    :initarg :proposed
    :reader request-message-proposed
    :documentation "是否为提议状态")
   (registration-method
    :initarg :registration-method
    :reader request-message-registration-method
    :documentation "注册方法")
   (registration-options
    :initarg :registration-options
    :reader request-message-registration-options
    :documentation "注册选项")
   (result
    :initarg :result
    :reader request-message-result
    :documentation "响应结果类型")
   (since
    :initarg :since
    :reader request-message-since
    :documentation "引入版本")))

;; notification-message - LSP 通知消息基类
;; 表示单向通知消息，不需要响应
(defclass notification-message ()
  ((deprecated
    :initarg :deprecated
    :reader notification-message-deprecated
    :documentation "是否已废弃")
   (documentation
    :initarg :documentation
    :reader notification-message-documentation
    :documentation "消息文档说明")
   (message-direction
    :initarg :message-direction
    :reader notification-message-message-direction
    :documentation "消息方向")
   (method
    :initarg :method
    :reader notification-message-method
    :documentation "通知方法名")
   (params
    :initarg :params
    :reader notification-message-params
    :documentation "通知参数类型")
   (proposed
    :initarg :proposed
    :reader notification-message-proposed
    :documentation "是否为提议状态")
   (registration-method
    :initarg :registration-method
    :reader notification-message-registration-method
    :documentation "注册方法")
   (registration-options
    :initarg :registration-options
    :reader notification-message-registration-options
    :documentation "注册选项")
   (since
    :initarg :since
    :reader notification-message-since
    :documentation "引入版本")))

;;; ============================================================================
;;; 消息定义宏
;;; ============================================================================

;; define-request-message - 定义请求消息类型
;; 参数: name - 消息名称
;;       default-initargs - 默认初始化参数（通常是 :method 和 :params）
(defmacro define-request-message (name () &body default-initargs)
  `(defclass ,name (request-message)
     ()
     (:default-initargs ,@default-initargs)))

;; define-notification-message - 定义通知消息类型
;; 参数: name - 消息名称
;;       default-initargs - 默认初始化参数
(defmacro define-notification-message (name () &body default-initargs)
  `(defclass ,name (notification-message)
     ()
     (:default-initargs ,@default-initargs)))

;;; ============================================================================
;;; 命名转换工具
;;; ============================================================================

;; param-case - 将字符串转换为 param-case 格式
;; 用于 JSON 键名的转换
(defun param-case (string)
  (format nil "~{~A~^/~}"
          (loop :for string-part :in (split-sequence:split-sequence #\/ string)
                :collect (cl-change-case:param-case string-part))))

;; pascal-to-lisp-case - 将 PascalCase 转换为 LISP-CASE
;; 用于将 JSON 属性名转换为 Lisp 槽名
(defun pascal-to-lisp-case (string)
  (string-upcase
   (if (alexandria:starts-with-subseq "_" string)
       (uiop:strcat "_" (param-case string))
       (param-case string))))

;; lisp-to-pascal-case - 将 LISP-CASE 转换为 PascalCase
;; 用于将 Lisp 槽名转换为 JSON 属性名
(defun lisp-to-pascal-case (string)
  (if (alexandria:starts-with-subseq "_" string)
      (uiop:strcat "_" (cl-change-case:camel-case string))
      (cl-change-case:camel-case string)))

;;; ============================================================================
;;; LSP 数据结构构造函数
;;; ============================================================================

;; make-lsp-map - 创建 LSP 映射对象
;; 参数: key-value-pairs - 键值对列表
;; 返回: 哈希表，键自动转换为 PascalCase
(defun make-lsp-map (&rest key-value-pairs)
  (let ((hash-table (make-hash-table :test 'equal)))
    (loop :for (key value) :on key-value-pairs :by #'cddr
          :do (let ((key (etypecase key
                           (string key)
                           (keyword (lisp-to-pascal-case (string key))))))
                (setf (gethash key hash-table) value)))
    hash-table))

;; make-lsp-array - 创建 LSP 数组对象
;; 参数: args - 数组元素
;; 返回: 向量
(defun make-lsp-array (&rest args)
  (apply #'vector args))

;; get-map - 从 LSP 映射中获取值
;; 参数: lsp-map - LSP 映射对象
;;       key - 键名
;;       default - 默认值（可选）
;; 返回: 对应的值或默认值
(defun get-map (lsp-map key &optional default)
  (gethash key lsp-map default))

;; lsp-array-p - 检查值是否为 LSP 数组
(defun lsp-array-p (value)
  (typep value 'lsp-array))

;; lsp-null-p - 检查值是否为 LSP null
(defun lsp-null-p (value)
  (eq value +null+))
