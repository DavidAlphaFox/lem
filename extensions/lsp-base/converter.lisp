;;;; converter.lisp - JSON 与协议对象转换器
;;;;
;;;; 本文件实现了 JSON 数据与 LSP 协议对象之间的双向转换。
;;;; LSP 使用 JSON 作为消息格式，需要将 JSON 转换为 Lisp 对象，反之亦然。
;;;;
;;;; 主要功能：
;;;; 1. convert-from-json: 将 JSON 数据转换为 LSP 协议对象
;;;; 2. convert-to-json: 将 LSP 协议对象转换为 JSON 数据
;;;;
;;;; 支持的转换类型：
;;;; - 基本类型：URI、整数、字符串、布尔值、null
;;;; - 复合类型：数组、映射、元组、接口
;;;; - 协议对象：protocol-object 的子类实例
;;;;
;;;; 相关文件：
;;;; - type.lisp: LSP 类型系统定义
;;;; - yason-utils.lisp: JSON 解析配置

(defpackage :lem-lsp-base/converter
  (:use :cl :lem-lsp-base/type)
  (:export :convert-from-json
           :convert-to-json))
(in-package :lem-lsp-base/converter)

(declaim (optimize (speed 0) (safety 3) (debug 3)))

;; Yason 解析选项：json-nulls-as-keyword = t, json-arrays-as-vectors = t
;; 这些配置确保 JSON 正确映射到 LSP 类型

;;; ============================================================================
;;; 辅助条件和函数
;;; ============================================================================

;; missing-value - 缺失值条件
;; 当必需的 JSON 字段缺失时使用
(define-condition missing-value ()
  ((key :initarg :key)
   (value :initarg :value)
   (type :initarg :type)))

;; assert-type - 断言值符合预期类型
;; 参数: value - 要检查的值
;;       type - 预期的类型
;; 当类型不匹配时发出警告并抛出 json-type-error
(defun assert-type (value type)
  (unless (typep value type)
    (log:warn "type mismatch: expected: ~A actual: ~A" type value)
    (error 'json-type-error :value value :type type))
  (values))

;; exist-key-p - 检查哈希表中是否存在指定键
;; 参数: hash-table - 哈希表
;;       key - 键名
;; 返回: T 如果键存在，否则 NIL
(defun exist-key-p (hash-table key)
  (let ((default '#:default))
    (not (eq default (gethash key hash-table default)))))

;; typexpand - 展开类型别名
;; 不同 Lisp 实现使用不同的函数
(defun typexpand (type)
  #+sbcl
  (sb-ext:typexpand type)
  #+ccl
  (ccl::type-expand type))

;;; ============================================================================
;;; JSON 到协议对象转换
;;; ============================================================================

;; convert-json-to-protocol-object - 将 JSON 哈希表转换为协议对象
;; 参数: hash-table - JSON 解析后的哈希表
;;       class - 目标协议类
;; 返回: 协议对象实例
(defun convert-json-to-protocol-object (hash-table class)
  (assert-type hash-table 'hash-table)
  (let ((initargs (loop :with default := '#:default
                        :for slot :in (protocol-class-slots class)
                        :for slot-name := (c2mop:slot-definition-name slot)
                        :for type := (c2mop:slot-definition-type slot)
                        :for key := (lisp-to-pascal-case (string slot-name))
                        :for value := (gethash key hash-table default)
                        :unless (eq value default)
                        :append (list (alexandria:make-keyword slot-name)
                                      (convert-from-json value type key)))))
    (apply #'make-instance class initargs)))

;; protocol-class-p - 检查类是否为协议类
;; 参数: class - 类对象
;; 返回: T 如果是 protocol-object 的子类
(defun protocol-class-p (class)
  (unless (c2mop:class-finalized-p class)
    (c2mop:finalize-inheritance class))
  (and (not (typep class 'c2mop:built-in-class))
       (not (null (member 'protocol-object
                          (c2mop:class-precedence-list class)
                          :key #'class-name)))))

;; convert-from-json - 将 JSON 值转换为指定类型的 Lisp 值
;; 参数: value - JSON 值
;;       type - 目标 LSP 类型
;;       context - 可选的上下文信息（用于错误报告）
;; 返回: 转换后的 Lisp 值
;;
;; 支持的类型：
;; - lsp-boolean: 布尔值（:null 视为 false）
;; - lsp-uri/lsp-document-uri: 字符串 URI
;; - lsp-integer/lsp-uinteger/lsp-decimal: 数字
;; - lsp-regexp/lsp-string: 字符串
;; - lsp-null: null 值
;; - (lsp-array element-type): 数组
;; - (lsp-map key-type value-type): 映射
;; - (lsp-tuple type1 type2 ...): 元组
;; - (lsp-interface properties): 接口
;; - (or type1 type2 ...): 联合类型
;; - protocol-object 子类: 协议对象
(defun convert-from-json (value type &optional context)
  (declare (ignorable context))
  (trivia:match type
    ('lsp-boolean
     (cond ((eq value :null)
            ;; 如果为 null，视为 false
            nil)
           (t
            (assert-type value type)
            value)))
    ((or 'lsp-uri
         'lsp-document-uri
         'lsp-integer
         'lsp-uinteger
         'lsp-decimal
         'lsp-regexp
         'lsp-string
         'lsp-null)
     (assert-type value type)
     value)
    ((list 'lsp-array element-type)
     (assert-type value 'vector)
     (map 'vector
          (lambda (element)
            (convert-from-json element element-type))
          value))
    ((list 'lsp-map key-type value-type)
     (assert-type value 'hash-table)
     (let ((hash-table (make-hash-table :test 'equal)))
       (maphash (lambda (key value)
                  (setf (gethash (convert-from-json key key-type) hash-table)
                        (convert-from-json value value-type)))
                value)
       hash-table))
    ((cons 'lsp-tuple types)
     (assert-type value 'vector)
     (unless (alexandria:length= value types)
       (error 'json-type-error :type type :value value))
     (map 'vector #'convert-from-json value types))
    ((list 'lsp-interface properties)
     (assert-type value 'hash-table)
     (loop :with hash-table := (make-hash-table :test 'equal)
           :for (name . options) :in properties
           :do (destructuring-bind (&key (initform nil initform-p) type &allow-other-keys)
                   options
                 (declare (ignore initform))
                 (let ((key (lisp-to-pascal-case (string name))))
                   (cond ((exist-key-p value key)
                          (setf (gethash key hash-table)
                                (convert-from-json (gethash key value) type)))
                         (initform-p ; 不是可选的
                          (error 'missing-value
                                 :key key
                                 :value value
                                 :type type)))))
           :finally (let* ((src-keys (alexandria:hash-table-keys value))
                           (dst-keys (alexandria:hash-table-keys hash-table))
                           (additional-keys (set-difference src-keys dst-keys :test #'equal)))
                      (loop :for key :in additional-keys
                            :do (setf (gethash key hash-table)
                                      (gethash key value)))
                      (return hash-table))))
    ((cons 'or types)
     (dolist (type types (error 'json-type-error :type type :value value))
       (handler-case
           (return (convert-from-json value type))
         (json-type-error ()))))
    (otherwise
     (let ((class (and (symbolp type)
                       (find-class type nil))))
       (if (and class (protocol-class-p class))
           (convert-json-to-protocol-object value class)
           (multiple-value-bind (type expanded)
               (typexpand type)
             (cond (expanded
                    (convert-from-json value type))
                   (t
                    ;; (assert-type value type)
                    value))))))))

;;; ============================================================================
;;; 协议对象到 JSON 转换
;;; ============================================================================

;; convert-to-json - 将 Lisp 值转换为 JSON 兼容格式
;; 这是一个泛型函数，为不同类型提供专门方法

;; protocol-object 转换：遍历所有槽并转换为 JSON 格式
(defmethod convert-to-json ((object protocol-object))
  (loop :with hash-table := (make-hash-table :test 'equal)
        :for slot :in (protocol-class-slots (class-of object))
        :for slot-name := (c2mop:slot-definition-name slot)
        :when (slot-boundp object slot-name)
        :do (let ((value (slot-value object slot-name))
                  (key (lisp-to-pascal-case (string slot-name))))
              (setf (gethash key hash-table)
                    (convert-to-json value)))
        :finally (return hash-table)))

;; 字符串直接返回
(defmethod convert-to-json ((object string))
  object)

;; 向量递归转换每个元素
(defmethod convert-to-json ((object vector))
  (map 'vector #'convert-to-json object))

;; 哈希表递归转换每个值
(defmethod convert-to-json ((object hash-table))
  (let ((hash-table (make-hash-table :test 'equal)))
    (maphash (lambda (k v)
               (setf (gethash k hash-table)
                     (convert-to-json v)))
             object)
    hash-table))

;; 其他类型直接返回（数字、关键字等）
(defmethod convert-to-json (object)
  object)
