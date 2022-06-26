(in-package :lem-base)

(export '(first-line-p
          last-line-p
          start-line-p
          end-line-p
          start-buffer-p
          end-buffer-p
          same-line-p
          move-point
          line-start
          line-end
          buffer-start
          buffer-end
          line-offset
          character-offset
          character-at
          line-string
          text-property-at
          put-text-property
          remove-text-property
          next-single-property-change
          previous-single-property-change
          insert-character
          insert-string
          delete-character
          erase-buffer
          region-beginning
          region-end
          map-region
          points-to-string
          count-characters
          delete-between-points
          count-lines
          apply-region-lines
          line-number-at-point
          point-column
          move-to-column
          position-at-point
          move-to-position
          point-bytes
          move-to-line
          check-marked
          set-current-mark
          blank-line-p
          skip-chars-forward
          skip-chars-backward
          insert-buffer
          buffer-text))

(defun same-line-p (point1 point2)
  "`point1`と`point2`が同じ位置ならT、それ以外ならNILを返します。"
  (assert (eq (point-buffer point1)
              (point-buffer point2)))
  (eq (point-line point1) (point-line point2)))

(defun first-line-p (point)
  "`point`が最初の行ならT、それ以外ならNILを返します。"
  (same-line-p point
               (buffer-start-point (point-buffer point))))

(defun last-line-p (point)
  "`point`が最後の行ならT、それ以外ならNILを返します。"
  (same-line-p point
               (buffer-end-point (point-buffer point))))

(defun start-line-p (point)
  "`point`が行頭ならT、それ以外ならNILを返します。"
  (zerop (point-charpos point)))

(defun end-line-p (point)
  "`point`が行末ならT、それ以外ならNILを返します。"
  (= (point-charpos point)
     (line-length (point-line point))))

(defun start-buffer-p (point)
  "`point`がバッファの最初の位置ならT、それ以外ならNILを返します。"
  (point<= point (buffer-start-point (point-buffer point))))

(defun end-buffer-p (point)
  "`point`がバッファの最後の位置ならT、それ以外ならNILを返します。"
  (point<= (buffer-end-point (point-buffer point)) point))

(defun %move-to-position (point linum line charpos)
  (assert (line-alive-p line))
  (assert (<= 0 charpos))
  (without-interrupts
    (point-change-line point linum line)
    (setf (point-charpos point) (min (line-length line) charpos)))
  point)

(defun move-point (point new-point)
  "`point`を`new-point`の位置に移動します。"
  (assert (eq (point-buffer point)
              (point-buffer new-point)))
  (%move-to-position point
                     (point-linum new-point)
                     (point-line new-point)
                     (point-charpos new-point)))

(defun line-start (point)
  "`point`を行頭に移動します。"
  (setf (point-charpos point) 0)
  point)

(defun line-end (point)
  "`point`を行末に移動します。"
  (setf (point-charpos point)
        (line-length (point-line point)))
  point)

(defun buffer-start (point)
  "`point`をバッファの最初の位置に移動します。"
  (move-point point (buffer-start-point (point-buffer point))))

(defun buffer-end (point)
  "`point`をバッファの最後の位置に移動します。"
  (move-point point (buffer-end-point (point-buffer point))))

(defun line-offset (point n &optional (charpos 0))
  "`point`を`n`が正の数なら下に、負の数なら上に行を移動し、移動後の`point`を返します。
`n`行先に行が無ければ`point`の位置はそのままでNILを返します。
`charpos`は移動後の行頭からのオフセットです。
"
  (cond
    ((plusp n)
     (do ((i n (1- i))
          (line (point-line point) (line-next line)))
         ((null line) nil)
       (when (zerop i)
         (%move-to-position point (+ (point-linum point) n)
                            line charpos)
         (return point))))
    ((minusp n)
     (do ((i n (1+ i))
          (line (point-line point) (line-prev line)))
         ((null line) nil)
       (when (zerop i)
         (%move-to-position point (+ (point-linum point) n)
                            line charpos)
         (return point))))
    (t
     (setf (point-charpos point)
           (if (< charpos 0)
               0
               (min charpos
                    (line-length (point-line point)))))
     point)))

(declaim (inline %character-offset))
(defun %character-offset (point n fn zero-fn)
  (cond ((zerop n) (when zero-fn (funcall zero-fn)))
        ((plusp n)
         (do ((line (point-line point) (line-next line))
              (linum (point-linum point) (1+ linum))
              (charpos (point-charpos point) 0))
             ((null line) nil)
           (let ((w (- (line-length line) charpos)))
             (when (<= n w)
               (return (funcall fn linum line (+ charpos n))))
             (decf n (1+ w)))))
        (t
         (setf n (- n))
         (do* ((line (point-line point) (line-prev line))
               (linum (point-linum point) (1- linum))
               (charpos (point-charpos point) (and line (line-length line))))
             ((null line) nil)
           (when (<= n charpos)
             (return (funcall fn linum line (- charpos n))))
           (decf n (1+ charpos))))))

(defun character-offset (point n)
  "`point`を`n`が正の数なら後に、負の数なら前に移動し、移動後の`point`を返します。
`n`文字先がバッファの範囲外なら`point`の位置はそのままでNILを返します。"
  (%character-offset point n
                     (lambda (linum line charpos)
                       (%move-to-position point linum line charpos)
                       point)
                     (lambda ()
                       point)))

(defun character-at (point &optional (offset 0))
  "`point`から`offset`ずらした位置の文字を返します。
バッファの範囲外ならNILを返します。"
  (%character-offset point offset
                     (lambda (linum line charpos)
                       (declare (ignore linum))
                       (line-char line charpos))
                     (lambda ()
                       (line-char (point-line point)
                                  (point-charpos point)))))

(defun line-string (point)
  "`point`の行の文字列を返します。"
  (line-str (point-line point)))

(defun text-property-at (point prop &optional (offset 0))
  "`point`から`offset`ずらした位置の`prop`のプロパティを返します。"
  (%character-offset point offset
                     (lambda (linum line charpos)
                       (declare (ignore linum))
                       (line-search-property line prop charpos))
                     (lambda ()
                       (line-search-property (point-line point)
                                             prop
                                             (point-charpos point)))))

(defun put-text-property (start-point end-point prop value)
  "`start-point`から`end-point`の間のテキストプロパティ`prop`を`value`にします。"
  (assert (eq (point-buffer start-point)
              (point-buffer end-point)))
  (%map-region start-point end-point
               (lambda (line start end)
                 (line-add-property line
                                    start
                                    (if (null end)
                                        (line-length line)
                                        end)
                                    prop
                                    value
                                    (null end)))))

(defun remove-text-property (start-point end-point prop)
  "`start-point`から`end-point`までのテキストプロパティ`prop`を削除します。"
  (assert (eq (point-buffer start-point)
              (point-buffer end-point)))
  (%map-region start-point end-point
               (lambda (line start end)
                 (line-remove-property line
                                       start
                                       (if (null end)
                                           (line-length line)
                                           end)
                                       prop))))

(defun next-single-property-change (point prop &optional limit-point)
  "`point`からテキストプロパティ`prop`の値が異なる位置まで後の方向に移動し、
移動後の`point`を返します。  
バッファの最後まで走査が止まらないか、`limit-point`を越えると走査を中断しNILを返します。"
  (let ((first-value (text-property-at point prop)))
    (with-point ((curr point))
      (loop
        (unless (character-offset curr 1)
          (return nil))
        (unless (eq first-value (text-property-at curr prop))
          (return (move-point point curr)))
        (when (and limit-point (point<= limit-point curr))
          (return nil))))))

(defun previous-single-property-change (point prop &optional limit-point)
  "`point`からテキストプロパティ`prop`の値が異なる位置まで前の方向に移動し、
移動後の`point`を返します。  
バッファの最初の位置まで走査が止まらないか、`limit-point`を越えると走査を中断しNILを返します。"
  (let ((first-value (text-property-at point prop -1)))
    (with-point ((curr point))
      (loop
        (unless (eq first-value (text-property-at curr prop -1))
          (return (move-point point curr)))
        (unless (character-offset curr -1)
          (return nil))
        (when (and limit-point (point> limit-point curr))
          (return nil))))))

(defun insert-character (point char &optional (n 1))
  "`point`に文字`char`を`n`回挿入します。"
  (loop :repeat n :do (insert-char/point point char))
  t)

(defun insert-string (point string &rest plist)
  "`point`に文字列`string`を挿入します。  
`plist`を指定すると`string`を挿入した範囲にテキストプロパティを設定します。"
  (if (null plist)
      (insert-string/point point string)
      (with-point ((start-point point))
        (insert-string/point point string)
        (let ((end-point (character-offset (copy-point start-point :temporary)
                                           (length string))))
          (loop :for (k v) :on plist :by #'cddr
                :do (put-text-property start-point end-point k v)))))
  t)

(defun delete-character (point &optional (n 1))
  "`point`から`n`個文字を削除し、削除した文字列を返します。 
`n`個の文字を削除する前にバッファの末尾に達した場合はNILを返します。"
  (when (minusp n)
    (unless (character-offset point n)
      (return-from delete-character nil))
    (setf n (- n)))
  (unless (end-buffer-p point)
    (let ((string (delete-char/point point n)))
      string)))

(defun erase-buffer (&optional (buffer (current-buffer)))
  "`buffer`のテキストをすべて削除します。"
  (buffer-start (buffer-point buffer))
  (delete-char/point (buffer-point buffer)
                     (count-characters (buffer-start-point buffer)
                                       (buffer-end-point buffer))))

(defun region-beginning (&optional (buffer (current-buffer)))
  "`buffer`内のリージョンの始まりの位置の`point`を返します。"
  (let ((start (buffer-point buffer))
        (end (buffer-mark buffer)))
    (if (point< start end)
        start
        end)))

(defun region-end (&optional (buffer (current-buffer)))
  "`buffer`内のリージョンの終わりの位置の`point`を返します。"
  (let ((start (buffer-point buffer))
        (end (buffer-mark buffer)))
    (if (point< start end)
        end
        start)))

(defun %map-region (start end function)
  (when (point< end start)
    (rotatef start end))
  (let ((start-line (point-line start))
        (end-line (point-line end)))
    (loop :for line := start-line :then (line-next line)
          :for firstp := (eq line start-line)
          :for lastp := (eq line end-line)
          :do (funcall function
                       line
                       (if firstp
                           (point-charpos start)
                           0)
                       (if lastp
                           (point-charpos end)
                           nil))
          :until lastp))
  (values))

(defun map-region (start end function)
  (%map-region start end
               (lambda (line start end)
                 (funcall function
                          (subseq (line-str line) start end)
                          (not (null end))))))

(defun points-to-string (start-point end-point)
  "`start-point`から`end-point`までの範囲の文字列を返します。"
  (assert (eq (point-buffer start-point)
              (point-buffer end-point)))
  (with-output-to-string (out)
    (map-region start-point end-point
                (lambda (string lastp)
                  (write-string string out)
                  (unless lastp
                    (write-char #\newline out))))))

(defun count-characters (start-point end-point)
  "`start-point`から`end-point`までの文字列の長さを返します。"
  (let ((count 0))
    (map-region start-point
                end-point
                (lambda (string lastp)
                  (incf count (length string))
                  (unless lastp
                    (incf count))))
    count))

(defun delete-between-points (start-point end-point)
  "`start-point`から`end-point`までの範囲を削除し、削除した文字列を返します。"
  (assert (eq (point-buffer start-point)
              (point-buffer end-point)))
  (unless (point< start-point end-point)
    (rotatef start-point end-point))
  (delete-char/point start-point
                     (count-characters start-point end-point)))

(defun count-lines (start-point end-point)
  "`start-point`から`end-point`までの行数を返します。"
  (assert (eq (point-buffer start-point)
              (point-buffer end-point)))
  (abs (- (point-linum start-point)
          (point-linum end-point))))

(defun apply-region-lines (start-point end-point function)
  "`start-point`から`end-point`の各行に対して
ポイントを引数に取る`function`を適用します。"
  (when (point< end-point start-point)
    (rotatef start-point end-point))
  (with-point ((start-point start-point :right-inserting)
               (end-point end-point :right-inserting)
               (point start-point))
    (loop :while (point<= start-point end-point)
          :do (funcall function (move-point point start-point))
              (unless (line-offset start-point 1)
                (return)))))

(defun line-number-at-point (point)
  "`point`の行番号を返します。"
  (point-linum point))

(defun point-column (point)
  "`point`の行頭からの列幅を返します。"
  (string-width (line-string point)
                :start 0
                :end (point-charpos point)
                :tab-size (variable-value 'tab-width :default point)))

(defun move-to-column (point column &optional force)
  "`point`を行頭から列幅`column`まで移動し、移動後の`point`を返します。
`force`が非NILの場合は、行の長さが`column`より少なければ空白を挿入して移動し、
`force`がNILの場合は、行末まで移動し、移動後の`point`を返します。"
  (line-end point)
  (let ((cur-column (point-column point)))
    (cond ((< column cur-column)
           (setf (point-charpos point)
                 (wide-index (line-string point)
                             column
                             :tab-size (variable-value 'tab-width :default point)))
           point)
          (force
           (insert-character point #\space (- column cur-column))
           (line-end point))
          (t
           (line-end point)))))

(defun position-at-point (point)
  "`point`のバッファの先頭からの1始まりのオフセットを返します。"
  (let ((offset (point-charpos point)))
    (do ((line (line-prev (point-line point)) (line-prev line)))
        ((null line) (1+ offset))
      (incf offset (1+ (line-length line))))))

(defun move-to-position (point position)
  "`point`をバッファの先頭からの1始まりのオフセット`position`に移動してその位置を返します。
`position`がバッファの範囲外なら`point`は移動せず、NILを返します。"
  (let ((line-number (line-number-at-point point))
        (charpos (point-charpos point)))
    (or (character-offset (buffer-start point) (1- position))
        (progn
          (move-to-line point line-number)
          (line-offset point 0 charpos)
          nil))))

(defun point-bytes (point)
  "`point`のバイト単位のバッファ先頭からのオフセットを返します。"
  (with-point ((point point))
    (let ((nbytes 0))
      (incf nbytes
            (babel:string-size-in-octets (line-string point)
                                         :end (point-charpos point)))
      (loop
        (unless (line-offset point -1) (return))
        (incf nbytes (1+ (babel:string-size-in-octets (line-string point)))))
      nbytes)))

(defun move-to-line (point line-number)
  "`point`を行番号`line-number`に移動し、移動後の位置を返します。
`line-number`がバッファの範囲外なら`point`は移動せず、NILを返します。"
  (let ((cur-linum (line-number-at-point point))
        (nlines (buffer-nlines (point-buffer point))))
    (cond ((or (> 1 line-number)
               (< nlines line-number))
           nil)
          ((= line-number cur-linum)
           point)
          ((< line-number cur-linum)
           (if (< line-number (- cur-linum line-number))
               (line-offset (buffer-start point) (1- line-number))
               (line-offset point (- line-number cur-linum))))
          (t
           (if (< (- line-number cur-linum) (- nlines line-number))
               (line-offset point (- line-number cur-linum))
               (line-offset (buffer-end point) (- line-number nlines)))))))

(defun check-marked ()
  "`current-buffer`内でマークが置かれていなければ`editor-error`を起こします。"
  (unless (buffer-mark (current-buffer))
    (editor-error "Not mark in this buffer")))

(defun set-current-mark (point)
  "`point`を現在のマークに設定します。"
  (let ((buffer (point-buffer point)))
    (setf (buffer-mark-p buffer) t)
    (cond ((buffer-mark buffer)
           (move-point (buffer-mark buffer) point))
          (t
           (setf (buffer-mark buffer)
                 (copy-point point :right-inserting)))))
  point)

(defun blank-line-p (point)
  "`point`のある行が空白だけなら、その空白の個数、それ以外ならnilを返します。"
  (let ((string (line-string point))
        (eof-p (last-line-p point))
        (count 0))
    (loop :for c :across string
          :do (unless (or (char= c #\space)
                          (char= c #\tab))
                (return-from blank-line-p nil))
              (incf count))
    (if eof-p
        count
        (1+ count))))

(defun skip-chars-internal (point test dir)
  (loop :for count :from 0
        :for c := (character-at point (if dir 0 -1))
        :do (when (or (null c)
                      (not (if (listp test)
                               (member c test)
                               (funcall test c))))
              (return count))
            (unless (character-offset point (if dir 1 -1))
              (return count))))

(defun skip-chars-forward (point test)
  "`point`からその位置の文字を`test`で評価して非NILの間、後の方向に移動します。  
`test`が文字のリストならその位置の文字が`test`のリスト内に含まれるか  
`test`が関数ならその位置の文字を引数として一つ取り、返り値が非NILであるか
"
  (skip-chars-internal point test t))

(defun skip-chars-backward (point test)
  "`point`からその位置の前の文字を`test`で評価して非NILの間、前の方向に移動します。  
`test`が文字のリストならその位置の前の文字が`test`のリスト内に含まれるか  
`test`が関数ならその位置の前の文字を引数として一つ取り、返り値が非NILであるか
"
  (skip-chars-internal point test nil))

(defun invoke-save-excursion (function)
  (let ((point (copy-point (current-point) :right-inserting))
        (mark (when (buffer-mark-p (current-buffer))
                (copy-point (buffer-mark (current-buffer))
                            :right-inserting))))
    (unwind-protect (funcall function)
      (setf (current-buffer) (point-buffer point))
      (move-point (current-point) point)
      (delete-point point)
      (when mark
        (set-current-mark mark)
        (delete-point mark)))))

(defun insert-buffer (point buffer)
  "`point`の位置に`buffer`内のテキストを挿入します。
`insert-string`との違いは`buffer`内のテキストプロパティも反映することです。"
  (loop :for line := (point-line (buffer-start-point buffer)) :then (line-next line)
        :while line
        :do (insert-string point (line-str line))
            (setf (line-plist (point-line point)) (line-plist line))
            (insert-character point #\newline)))

(defun buffer-text (buffer)
  (points-to-string (buffer-start-point buffer)
                    (buffer-end-point buffer)))