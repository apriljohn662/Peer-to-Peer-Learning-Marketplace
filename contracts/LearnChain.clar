;; LearnChain - Peer-to-Peer Learning Marketplace

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u1000))
(define-constant ERR_SESSION_NOT_FOUND (err u1001))
(define-constant ERR_INVALID_STATUS (err u1002))
(define-constant ERR_INSUFFICIENT_BALANCE (err u1003))
(define-constant ERR_ALREADY_REGISTERED (err u1004))
(define-constant ERR_NOT_REGISTERED (err u1005))
(define-constant ERR_SESSION_EXPIRED (err u1006))
(define-constant ERR_INVALID_RATING (err u1007))
(define-constant ERR_PAYMENT_FAILED (err u1008))

(define-data-var next-session-id uint u1)
(define-data-var platform-fee-percent uint u5)

(define-map tutors principal {
    name: (string-ascii 50),
    subject: (string-ascii 30),
    hourly-rate: uint,
    rating: uint,
    total-sessions: uint,
    is-active: bool
})

(define-map students principal {
    name: (string-ascii 50),
    total-sessions: uint,
    is-active: bool
})

(define-map sessions uint {
    student: principal,
    tutor: principal,
    subject: (string-ascii 30),
    duration: uint,
    rate: uint,
    total-cost: uint,
    status: (string-ascii 20),
    created-at: uint,
    starts-at: uint,
    completed-at: (optional uint)
})

(define-map session-payments uint {
    amount: uint,
    escrowed: bool,
    released: bool,
    platform-fee: uint
})

(define-map session-reviews uint {
    student-rating: (optional uint),
    tutor-rating: (optional uint),
    student-review: (optional (string-ascii 200)),
    tutor-review: (optional (string-ascii 200))
})

(define-public (register-tutor (name (string-ascii 50)) (subject (string-ascii 30)) (hourly-rate uint))
    (let ((tutor-data (map-get? tutors tx-sender)))
        (if (is-some tutor-data)
            ERR_ALREADY_REGISTERED
            (begin
                (map-set tutors tx-sender {
                    name: name,
                    subject: subject,
                    hourly-rate: hourly-rate,
                    rating: u5,
                    total-sessions: u0,
                    is-active: true
                })
                (ok true)
            )
        )
    )
)

(define-public (register-student (name (string-ascii 50)))
    (let ((student-data (map-get? students tx-sender)))
        (if (is-some student-data)
            ERR_ALREADY_REGISTERED
            (begin
                (map-set students tx-sender {
                    name: name,
                    total-sessions: u0,
                    is-active: true
                })
                (ok true)
            )
        )
    )
)

(define-public (create-session (tutor principal) (subject (string-ascii 30)) (duration uint) (starts-at uint))
    (let (
        (session-id (var-get next-session-id))
        (tutor-data (unwrap! (map-get? tutors tutor) ERR_NOT_REGISTERED))
        (student-data (unwrap! (map-get? students tx-sender) ERR_NOT_REGISTERED))
        (hourly-rate (get hourly-rate tutor-data))
        (total-cost (* duration hourly-rate))
        (platform-fee (/ (* total-cost (var-get platform-fee-percent)) u100))
    )
        (if (>= (stx-get-balance tx-sender) (+ total-cost platform-fee))
            (begin
                (try! (stx-transfer? (+ total-cost platform-fee) tx-sender (as-contract tx-sender)))
                (map-set sessions session-id {
                    student: tx-sender,
                    tutor: tutor,
                    subject: subject,
                    duration: duration,
                    rate: hourly-rate,
                    total-cost: total-cost,
                    status: "pending",
                    created-at: stacks-block-height,
                    starts-at: starts-at,
                    completed-at: none
                })
                (map-set session-payments session-id {
                    amount: total-cost,
                    escrowed: true,
                    released: false,
                    platform-fee: platform-fee
                })
                (var-set next-session-id (+ session-id u1))
                (ok session-id)
            )
            ERR_INSUFFICIENT_BALANCE
        )
    )
)

(define-public (accept-session (session-id uint))
    (let ((session-data (unwrap! (map-get? sessions session-id) ERR_SESSION_NOT_FOUND)))
        (if (is-eq (get tutor session-data) tx-sender)
            (if (is-eq (get status session-data) "pending")
                (begin
                    (map-set sessions session-id (merge session-data { status: "accepted" }))
                    (ok true)
                )
                ERR_INVALID_STATUS
            )
            ERR_NOT_AUTHORIZED
        )
    )
)

(define-public (start-session (session-id uint))
    (let ((session-data (unwrap! (map-get? sessions session-id) ERR_SESSION_NOT_FOUND)))
        (if (is-eq (get tutor session-data) tx-sender)
            (if (is-eq (get status session-data) "accepted")
                (if (>= stacks-block-height (get starts-at session-data))
                    (begin
                        (map-set sessions session-id (merge session-data { status: "active" }))
                        (ok true)
                    )
                    ERR_INVALID_STATUS
                )
                ERR_INVALID_STATUS
            )
            ERR_NOT_AUTHORIZED
        )
    )
)

(define-public (complete-session (session-id uint))
    (let ((session-data (unwrap! (map-get? sessions session-id) ERR_SESSION_NOT_FOUND)))
        (if (or (is-eq (get student session-data) tx-sender) (is-eq (get tutor session-data) tx-sender))
            (if (is-eq (get status session-data) "active")
                (begin
                    (map-set sessions session-id (merge session-data { 
                        status: "completed",
                        completed-at: (some stacks-block-height)
                    }))
                    (try! (release-payment session-id))
                    (try! (update-session-counts session-id))
                    (ok true)
                )
                ERR_INVALID_STATUS
            )
            ERR_NOT_AUTHORIZED
        )
    )
)

(define-public (cancel-session (session-id uint))
    (let ((session-data (unwrap! (map-get? sessions session-id) ERR_SESSION_NOT_FOUND)))
        (if (or (is-eq (get student session-data) tx-sender) (is-eq (get tutor session-data) tx-sender))
            (if (or (is-eq (get status session-data) "pending") (is-eq (get status session-data) "accepted"))
                (begin
                    (map-set sessions session-id (merge session-data { status: "cancelled" }))
                    (try! (refund-payment session-id))
                    (ok true)
                )
                ERR_INVALID_STATUS
            )
            ERR_NOT_AUTHORIZED
        )
    )
)

(define-public (rate-session (session-id uint) (rating uint) (review (string-ascii 200)))
    (let (
        (session-data (unwrap! (map-get? sessions session-id) ERR_SESSION_NOT_FOUND))
        (existing-review (default-to { student-rating: none, tutor-rating: none, student-review: none, tutor-review: none } (map-get? session-reviews session-id)))
    )
        (if (and (>= rating u1) (<= rating u5))
            (if (is-eq (get status session-data) "completed")
                (if (is-eq (get student session-data) tx-sender)
                    (begin
                        (map-set session-reviews session-id (merge existing-review {
                            student-rating: (some rating),
                            student-review: (some review)
                        }))
                        (try! (update-tutor-rating (get tutor session-data) rating))
                        (ok true)
                    )
                    (if (is-eq (get tutor session-data) tx-sender)
                        (begin
                            (map-set session-reviews session-id (merge existing-review {
                                tutor-rating: (some rating),
                                tutor-review: (some review)
                            }))
                            (ok true)
                        )
                        ERR_NOT_AUTHORIZED
                    )
                )
                ERR_INVALID_STATUS
            )
            ERR_INVALID_RATING
        )
    )
)

(define-public (update-tutor-profile (name (string-ascii 50)) (subject (string-ascii 30)) (hourly-rate uint))
    (let ((tutor-data (unwrap! (map-get? tutors tx-sender) ERR_NOT_REGISTERED)))
        (map-set tutors tx-sender (merge tutor-data {
            name: name,
            subject: subject,
            hourly-rate: hourly-rate
        }))
        (ok true)
    )
)

(define-public (deactivate-account)
    (let ((tutor-data (map-get? tutors tx-sender))
          (student-data (map-get? students tx-sender)))
        (if (is-some tutor-data)
            (map-set tutors tx-sender (merge (unwrap-panic tutor-data) { is-active: false }))
            (if (is-some student-data)
                (map-set students tx-sender (merge (unwrap-panic student-data) { is-active: false }))
                false
            )
        )
        (ok true)
    )
)

(define-public (set-platform-fee (new-fee uint))
    (if (is-eq tx-sender CONTRACT_OWNER)
        (if (<= new-fee u20)
            (begin
                (var-set platform-fee-percent new-fee)
                (ok true)
            )
            (err u999)
        )
        ERR_NOT_AUTHORIZED
    )
)

(define-private (release-payment (session-id uint))
    (let (
        (session-data (unwrap! (map-get? sessions session-id) ERR_SESSION_NOT_FOUND))
        (payment-data (unwrap! (map-get? session-payments session-id) ERR_PAYMENT_FAILED))
    )
        (if (get escrowed payment-data)
            (if (not (get released payment-data))
                (let ((tutor-payment (get amount payment-data))
                      (platform-fee (get platform-fee payment-data)))
                    (try! (as-contract (stx-transfer? tutor-payment tx-sender (get tutor session-data))))
                    (try! (as-contract (stx-transfer? platform-fee tx-sender CONTRACT_OWNER)))
                    (map-set session-payments session-id (merge payment-data { released: true }))
                    (ok true)
                )
                (ok true)
            )
            ERR_PAYMENT_FAILED
        )
    )
)

(define-private (refund-payment (session-id uint))
    (let (
        (session-data (unwrap! (map-get? sessions session-id) ERR_SESSION_NOT_FOUND))
        (payment-data (unwrap! (map-get? session-payments session-id) ERR_PAYMENT_FAILED))
    )
        (if (get escrowed payment-data)
            (if (not (get released payment-data))
                (let ((refund-amount (+ (get amount payment-data) (get platform-fee payment-data))))
                    (try! (as-contract (stx-transfer? refund-amount tx-sender (get student session-data))))
                    (map-set session-payments session-id (merge payment-data { 
                        escrowed: false,
                        released: true 
                    }))
                    (ok true)
                )
                (ok true)
            )
            (ok true)
        )
    )
)

(define-private (update-session-counts (session-id uint))
    (let ((session-data (unwrap! (map-get? sessions session-id) ERR_SESSION_NOT_FOUND)))
        (let (
            (tutor-data (unwrap! (map-get? tutors (get tutor session-data)) ERR_NOT_REGISTERED))
            (student-data (unwrap! (map-get? students (get student session-data)) ERR_NOT_REGISTERED))
        )
            (map-set tutors (get tutor session-data) (merge tutor-data {
                total-sessions: (+ (get total-sessions tutor-data) u1)
            }))
            (map-set students (get student session-data) (merge student-data {
                total-sessions: (+ (get total-sessions student-data) u1)
            }))
            (ok true)
        )
    )
)

(define-private (update-tutor-rating (tutor principal) (new-rating uint))
    (let ((tutor-data (unwrap! (map-get? tutors tutor) ERR_NOT_REGISTERED)))
        (let (
            (current-rating (get rating tutor-data))
            (total-sessions (get total-sessions tutor-data))
            (weighted-rating (if (> total-sessions u0)
                (/ (+ (* current-rating total-sessions) new-rating) (+ total-sessions u1))
                new-rating
            ))
        )
            (map-set tutors tutor (merge tutor-data { rating: weighted-rating }))
            (ok true)
        )
    )
)

(define-read-only (get-tutor (tutor principal))
    (map-get? tutors tutor)
)

(define-read-only (get-student (student principal))
    (map-get? students student)
)

(define-read-only (get-session (session-id uint))
    (map-get? sessions session-id)
)

(define-read-only (get-session-payment (session-id uint))
    (map-get? session-payments session-id)
)

(define-read-only (get-session-review (session-id uint))
    (map-get? session-reviews session-id)
)

(define-read-only (get-platform-fee)
    (var-get platform-fee-percent)
)

(define-read-only (get-next-session-id)
    (var-get next-session-id)
)

(define-read-only (calculate-session-cost (duration uint) (hourly-rate uint))
    (let (
        (base-cost (* duration hourly-rate))
        (platform-fee (/ (* base-cost (var-get platform-fee-percent)) u100))
    )
        {
            base-cost: base-cost,
            platform-fee: platform-fee,
            total-cost: (+ base-cost platform-fee)
        }
    )
)

(define-read-only (get-active-tutors-by-subject (subject (string-ascii 30)))
    (ok subject)
)

(define-read-only (is-session-expired (session-id uint))
    (match (map-get? sessions session-id)
        session-data 
        (let ((session-end (+ (get starts-at session-data) (get duration session-data))))
            (and 
                (is-eq (get status session-data) "active")
                (> stacks-block-height (+ session-end u144))
            )
        )
        false
    )
)

(define-public (emergency-cancel-expired-session (session-id uint))
    (if (is-session-expired session-id)
        (let ((session-data (unwrap! (map-get? sessions session-id) ERR_SESSION_NOT_FOUND)))
            (begin
                (map-set sessions session-id (merge session-data { status: "expired" }))
                (try! (refund-payment session-id))
                (ok true)
            )
        )
        ERR_INVALID_STATUS
    )
)

(define-public (withdraw-platform-fees)
    (if (is-eq tx-sender CONTRACT_OWNER)
        (let ((contract-balance (stx-get-balance (as-contract tx-sender))))
            (if (> contract-balance u0)
                (begin
                    (try! (as-contract (stx-transfer? contract-balance tx-sender CONTRACT_OWNER)))
                    (ok contract-balance)
                )
                (ok u0)
            )
        )
        ERR_NOT_AUTHORIZED
    )
)
